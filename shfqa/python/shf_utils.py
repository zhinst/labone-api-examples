"""
Zurich Instruments LabOne Python API Utility Classes for SHF.
"""

import time
import numpy as np

from zhinst.utils import assert_node_changes_to_expected_value


class Shfqa:
    """
    Class providing common and reusable functionality for Zurich Instruments SHFQA devices. Methods
    are wrappers around the ziPython API enabling control over channels, generators, sequencers,
    integration units, result loggers and the scope.

    Instance attributes upon initialization:

        _device_id (str): identifier of the SHFQA device on which to use the functionality bundled
                          in this class, e.g. `dev12004` or 'shf-dev12004'

        _daq (ziDAQServer): instance of a Zurich Instruments API session connected to a Data Server.
                            Note that the device with identifier _device_id is assumed to already be
                            connected to this instance.

    """

    MAX_SIGNAL_GENERATOR_WAVEFORM_LENGTH = 4 * 2 ** 10
    MAX_SIGNAL_GENERATOR_CARRIER_COUNT = 16
    SAMPLING_FREQUENCY = 2e9

    def __init__(self, device_id, daq):
        self._device_id = device_id
        self._daq = daq

    def load_sequencer_program(self, channel_index, sequencer_program):
        """Compiles and loads a program to a specified sequencer.

        Arguments:

          channel_index (int): index specifying to which sequencer the program below
                               is uploaded - there is one sequencer per channel

          sequencer_program (str): sequencer program to be uploaded

        """

        # start by resetting the sequencer
        self._daq.setInt(
            f"/{self._device_id}/qachannels/{channel_index}/generator/reset",
            1,
        )
        self._daq.sync()

        timeout_compile = 10
        timeout_ready = 10

        awg_module = self._daq.awgModule()
        awg_module.set("device", self._device_id)
        awg_module.set("index", channel_index)
        awg_module.execute()

        t_start = time.time()
        awg_module.set("compiler/sourcestring", sequencer_program)
        timeout_occurred = False

        # start the compilation and upload
        compiler_status = awg_module.getInt("compiler/status")
        while compiler_status == -1 and not timeout_occurred:
            if time.time() - t_start > timeout_compile:
                # a timeout occurred
                timeout_occurred = True
                break
            # wait
            time.sleep(0.1)
            # query new status
            compiler_status = awg_module.getInt("compiler/status")

        # check the status after compilation and upload
        if timeout_occurred or compiler_status != 0:
            # an info, warning or error occurred - check what it is
            compiler_status = awg_module.getInt("compiler/status")
            statusstring = awg_module.getString("compiler/statusstring")
            if compiler_status == 2:
                print(
                    f"Compiler info or warning for channel {channel_index}:\n"
                    + statusstring
                )
            elif timeout_occurred:
                raise RuntimeError(
                    f"Timeout during program compilation for channel {channel_index} after \
                        {timeout_compile} s,\n"
                    + statusstring
                )
            else:
                raise RuntimeError(
                    f"Failed to compile program for channel {channel_index},\n"
                    + statusstring
                )

        # wait until the device becomes ready after program upload
        assert_node_changes_to_expected_value(
            self._daq,
            f"/{self._device_id}/qachannels/{channel_index}/generator/ready",
            1,
            sleep_time=0.1,
            max_repetitions=int(timeout_ready / 0.1),
        )
        time.sleep(0.1)

    def configure_scope(
        self,
        input_select,
        num_samples,
        trigger_input="channel0_sequencer_monitor0",
        num_segments=1,
        num_averages=1,
        trigger_delay=0,
    ):
        """Configures the scope for a measurement.

        Arguments:

            input_select (dict): keys (int) map a specific scope channel with a signal source (str),
                                 e.g. "channel0_signal_input"

            trigger_input (str): specifies the trigger source of the scope acquisition

            num_segments (int): number of distinct scope shots to be returned after ending the
                                acquisition

            num_averages (int): specifies how many times each segment should be averaged on
                                hardware; to finish a scope acquisition, the number of issued
                                triggers must be equal to num_segments * num_averages

            trigger_delay (int): delay in samples specifying the time between the start of data
                                 acquisition and reception of a trigger

        """

        self._daq.setInt(f"/{self._device_id}/scopes/0/segments/count", num_segments)
        if num_segments > 1:
            self._daq.setInt(f"/{self._device_id}/scopes/0/segments/enable", 1)
        else:
            self._daq.setInt(f"/{self._device_id}/scopes/0/segments/enable", 0)

        if num_averages > 1:
            self._daq.setInt(f"/{self._device_id}/scopes/0/averaging/enable", 1)
        else:
            self._daq.setInt(f"/{self._device_id}/scopes/0/averaging/enable", 0)
        self._daq.setInt(
            f"/{self._device_id}/scopes/0/averaging/count",
            num_averages,
        )

        self._daq.setInt(f"/{self._device_id}/scopes/0/channels/*/enable", 0)
        for channel, selected_input in input_select.items():
            self._daq.setString(
                f"/{self._device_id}/scopes/0/channels/{channel}/inputselect",
                selected_input,
            )
            self._daq.setInt(
                f"/{self._device_id}/scopes/0/channels/{channel}/enable", 1
            )

        self._daq.setDouble(f"/{self._device_id}/scopes/0/trigger/delay", trigger_delay)
        self._daq.setString(
            f"/{self._device_id}/scopes/0/trigger/channel",
            trigger_input,
        )

        self._daq.setInt(f"/{self._device_id}/scopes/0/length", num_samples)

    def get_scope_data(self, time_out=1):
        """Queries the scope for data once it has been triggered and finished the acquisition.

        Arguments:

          time_out (optional float): maximum time to wait for the scope data in seconds

        Returns:

          Three-element tuple with:

          recorded_data (array): contains an array per scope channel with the recorded data

          recorded_data_range (array): full scale range of each scope channel

          scope_time (array): relative acquisition time for each point in recorded_data in
                              seconds starting from 0

        """

        # wait until scope has been triggered
        sleep_time = 0.005
        num_loops = int(time_out / sleep_time)
        assert_node_changes_to_expected_value(
            self._daq,
            f"/{self._device_id}/scopes/0/enable",
            0,
            sleep_time=sleep_time,
            max_repetitions=num_loops,
        )

        # read and post-process the recorded data
        recorded_data = [[], [], [], []]
        recorded_data_range = [0.0, 0.0, 0.0, 0.0]
        num_bits_of_adc = 14
        max_adc_range = 2 ** (num_bits_of_adc - 1)

        channels = range(4)
        for channel in channels:
            if self._daq.getInt(
                f"/{self._device_id}/scopes/0/channels/{channel}/enable"
            ):
                path = f"/{self._device_id}/scopes/0/channels/{channel}/wave"
                data = self._daq.get(path.lower(), flat=True)
                vector = data[path]

                recorded_data[channel] = vector[0]["vector"]
                averagecount = vector[0]["properties"]["averagecount"]
                scaling = vector[0]["properties"]["scaling"]
                voltage_per_lsb = scaling * averagecount
                recorded_data_range[channel] = voltage_per_lsb * max_adc_range

        # generate the time base
        scope_time = [[], [], [], []]
        decimation_rate = 2 ** self._daq.getInt(f"/{self._device_id}/scopes/0/time")
        sampling_rate = Shfqa.SAMPLING_FREQUENCY / decimation_rate  # [Hz]
        for channel in channels:
            scope_time[channel] = (
                np.array(range(0, len(recorded_data[channel]))) / sampling_rate
            )

        return recorded_data, recorded_data_range, scope_time

    def enable_sequencer(self, channel_index):
        """Starts the sequencer of a specific channel.

        Arguments:

          channel_index (int): index specifying which sequencer to enable - there is one
                               sequencer per channel

        """

        enable_path = f"/{self._device_id}/qachannels/{channel_index}/generator/enable"
        self._daq.setInt(enable_path, 1)
        assert_node_changes_to_expected_value(self._daq, enable_path, 1)

    def write_to_waveform_memory(self, channel_index, waveforms):
        """Writes pulses to the waveform memory of a specified generator.

        Arguments:

          channel_index (int): index specifying which generator the waveforms below
                               are written to - there is one generator per channel

          waveforms (dict): dictionary of waveforms, the key specifies the slot to which
                            to write the value which is a complex array containing the
                            waveform samples

        """

        for slot, waveform in waveforms.items():
            self._daq.setVector(
                f"/{self._device_id}/qachannels/{channel_index}/generator/waveforms/{slot}/wave",
                waveform,
            )

    def start_continuous_sw_trigger(self, num_triggers, wait_time):
        """Issues a specified number of software triggers with a certain wait time in between.

        Arguments:

          num_triggers (int): number of triggers to be issued

          wait_time (float): time between triggers in seconds

        """

        min_wait_time = 0.02
        wait_time = max(min_wait_time, wait_time)
        for _ in range(num_triggers):
            self._daq.setInt(f"/{self._device_id}/system/swtriggers/0/single", 1)
            time.sleep(wait_time)

    def enable_scope(self, single=1):
        """Enables the scope.

        Arguments:

          single (int): 0 = continuous mode, 1 = single-shot

        """

        self._daq.setInt(f"/{self._device_id}/scopes/0/single", single)

        path = f"/{self._device_id}/scopes/0/enable"
        if self._daq.getInt(path) == 1:
            self._daq.setInt(path, 0)
            assert_node_changes_to_expected_value(self._daq, path, 0)
        self._daq.syncSetInt(path, 1)

    def configure_weighted_integration(
        self, channel_index, weights, integration_delay=0
    ):
        """Configures the weighted integration on a specified channel.

        Arguments:

          channel_index (int): index specifying which group of integration units
                               the integration weights should be uploaded to - each
                               channel is associated with a number of integration
                               units that depend on available device options. Please
                               refer to the SHFQA manual for more details

          weights (dict): dictionary containing the complex weight vectors, where keys
                          correspond to the indices of the integration units to be configured

          integration_delay (optional float): delay in seconds before starting readout

        """

        assert len(weights) > 0, "'weights' cannot be empty."

        integration_path = (
            f"/{self._device_id}/qachannels/{channel_index}/readout/integration/"
        )

        for integration_unit, weight in weights.items():
            self._daq.setVector(
                integration_path + f"weights/{integration_unit}/wave", weight
            )

        integration_length = len(weights[0])
        self._daq.setInt(integration_path + "length", integration_length)
        self._daq.setDouble(integration_path + "delay", integration_delay)

    def configure_result_logger(
        self,
        channel_index,
        result_length,
        num_averages=1,
        result_source="result_of_integration",
    ):
        """Configures a specified result logger for readout mode.

        Arguments:

          channel_index (int): index specifying which result logger to configure - there is one
                               result logger per channel

          result_length (int): number of results to be returned by the result logger

          num_averages (optional int): number of averages, will be rounded to 2^n

          result_source (optional str): string-based tag to select the result source, e.g.
                                        "result_of_integration" or "result_of_discrimination".

        """

        result_path = f"/{self._device_id}/qachannels/{channel_index}/readout/result/"
        self._daq.setInt(result_path + "length", result_length)
        self._daq.setInt(result_path + "averages", num_averages)
        self._daq.setString(result_path + "source", result_source)

    def enable_result_logger(self, channel_index):
        """Resets and enables a specified result logger.

        Arguments:

          channel_index (int): index specifying which result logger to enable - there is one
                               result logger per channel

        """

        enable_path = (
            f"/{self._device_id}/qachannels/{channel_index}/readout/result/enable"
        )
        # reset the result logger if some old measurement is still running
        if self._daq.getInt(enable_path) != 0:
            self._daq.setInt(enable_path, 0)
            assert_node_changes_to_expected_value(self._daq, enable_path, 0)
        self._daq.setInt(enable_path, 1)
        assert_node_changes_to_expected_value(self._daq, enable_path, 1)

    def get_result_logger_data(self, channel_index, time_out=1):
        """Waits until a specified result logger finished recording and returns the measured data.

        Arguments:

          channel_index (int): index specifying which result logger to query results from - there
                               is one result logger per channel

          time_out (optional float): maximum time to wait for data in seconds

        Returns:

          result (array): array containing the result logger data

        """

        sleep_time = 0.05
        num_loops = int(time_out / sleep_time)
        assert_node_changes_to_expected_value(
            self._daq,
            f"/{self._device_id}/qachannels/{channel_index}/readout/result/enable",
            0,
            sleep_time=sleep_time,
            max_repetitions=num_loops,
        )
        self._daq.sync()

        data = self._daq.get(
            f"/{self._device_id}/qachannels/{channel_index}/readout/result/data/*/wave",
            flat=True,
        )

        result = np.array([(lambda x: x[0]["vector"])(d) for d in data.values()])
        return result

    def configure_channel(
        self, channel_index, input_range, output_range, center_frequency, mode
    ):
        """Configures the RF input and output of a specified channel.

        Arguments:

          channel_index (int): index specifying which channel to configure

          input_range (int): maximal range of the signal input power in dbM

          output_range (int): maximal range of the signal output power in dbM

          center_frequency (float): center Frequency of the analysis band

          mode (str): select between "spectroscopy" and "readout" mode.

        """

        path = f"/{self._device_id}/qachannels/{channel_index}/"

        self._daq.setInt(path + "input/range", input_range)
        self._daq.setInt(path + "output/range", output_range)

        self._daq.setDouble(path + "centerfreq", center_frequency)

        self._daq.setInt(path + "input/on", 1)
        self._daq.setInt(path + "output/on", 1)
        self._daq.setString(path + "mode", mode)

    def configure_sequencer_triggering(
        self, channel_index, aux_trigger, play_pulse_delay=0
    ):
        """Configures the triggering of a specified sequencer.

        Arguments:

          channel_index (int): index specifying on which sequencer to configure the
                               triggering - there is one sequencer per channel

          aux_trigger (string): alias for the trigger used in the sequencer

          play_pulse_delay (optional float): delay in seconds before the start of waveform playback

        """

        self._daq.setString(
            f"/{self._device_id}/qachannels/{channel_index}/generator/auxtriggers/0/channel",
            aux_trigger,
        )
        self._daq.setDouble(
            f"/{self._device_id}/qachannels/{channel_index}/generator/delay",
            play_pulse_delay,
        )
