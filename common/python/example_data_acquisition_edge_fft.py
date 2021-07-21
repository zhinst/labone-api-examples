# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Python API Example for using the FFT feature of the Data Acquisition Core Module. This
example demonstrates how to get FFTs from triggered bursts of demodulator data when a
demodulator's R value is larger than a specified threshold using an edge
trigger.

The Data Acquisition Module implements software triggering which operates
analogously to the types of triggering found in laboratory oscilloscopes. The
Data Acquisition Module has a non-blocking (asynchronous) interface, it starts it's
own thread to communicate with the data server.

Note: This example requires a feedback cable between Signal Output 1 and Signal
Input 1 and changes the signal output's amplitude in order to create a signal
upon which to trigger.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_data_acquisition_edge_fft.py [options] <device_id>
    example_data_acquisition_edge_fft.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help                 Show this screen.
    -a --amplitude AMPLITUDE  The amplitude to set on the signal output. [default: 0.25]
    --no-plot                 Hide plot of the recorded data.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt


def run_example(device_id: str, amplitude: float = 0.25, plot: bool = True):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    err_msg = "This example only supports instruments with demodulators."
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id,
        apilevel_example,
        required_devtype=".*LI|.*IA|.*IS",
        required_err_msg=err_msg,
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all device configurations. The values below may be
    # changed if the instrument has multiple input/output channels and/or either
    # the Multifrequency or Multidemodulator options installed.
    out_channel = 0
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(props)
    in_channel = 0
    demod_index = 0
    osc_index = 0
    demod_rate = 10e3
    time_constant = 8e-5
    frequency = 400e3
    exp_setting = [
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        ["/%s/sigins/%d/imp50" % (device, in_channel), 0],
        ["/%s/sigins/%d/range" % (device, in_channel), 3 * amplitude],
        ["/%s/demods/%d/enable" % (device, demod_index), 1],
        ["/%s/demods/%d/rate" % (device, demod_index), demod_rate],
        ["/%s/demods/%d/adcselect" % (device, demod_index), in_channel],
        ["/%s/demods/%d/order" % (device, demod_index), 4],
        ["/%s/demods/%d/timeconstant" % (device, demod_index), time_constant],
        ["/%s/demods/%d/oscselect" % (device, demod_index), osc_index],
        ["/%s/demods/%d/harmonic" % (device, demod_index), 1],
        ["/%s/oscs/%d/freq" % (device, osc_index), frequency],
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), 1],
        [
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            amplitude,
        ],
    ]
    daq.set(exp_setting)

    # Wait for the demodulator filter to settle.
    time.sleep(10 * time_constant)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that 1. the settings have taken effect on the device before issuing
    # the poll() command and 2. clear the API's data buffers. Note: the sync()
    # must be issued after waiting for the demodulator filter to settle above.
    daq.sync()

    # Create an instance of the Data Acquisition Module.
    daq_module = daq.dataAcquisitionModule()

    # Below we will generate num_pulses pulses on the signal outputs in order to
    # demonstrate the triggering functionality. We'll configure the Software
    # Trigger's threshold according to these levels.
    sigouts_high = 1.5 * amplitude
    sigouts_low = 1.0 * amplitude
    num_pulses = 20

    # Configure the Data Acquisition Module.
    # Set the device that will be used for the trigger - this parameter must be set.
    daq_module.set("device", device)
    # We will trigger on the demodulator sample's R value.
    trigger_path = "/%s/demods/%d/sample.r" % (device, demod_index)
    triggernode = trigger_path
    daq_module.set("triggernode", triggernode)
    # Use an edge trigger.
    daq_module.set("type", 1)  # 1 = edge
    # Trigger on the positive edge.
    daq_module.set("edge", 1)  # 1 = positive
    # The set the trigger level.
    # Scale by 1/sqrt(2) due to the demodulator's R RMS value.
    trigger_level = 0.5 * (sigouts_low + sigouts_high) / np.sqrt(2)
    print(f"Setting 0/level to {trigger_level:.3f}.")
    daq_module.set("level", trigger_level)
    # Set the trigger hysteresis to a percentage of the trigger level: This
    # ensures that triggering is robust in the presence of noise. The trigger
    # becomes armed when the signal passes through the hysteresis value and will
    # then actually trigger if the signal additionally passes through the
    # trigger level. The hysteresis value is applied negatively for a positive
    # edge trigger relative to the trigger level (positively for a negative edge
    # trigger).
    trigger_hysteresis = 0.05 * trigger_level
    print(f"Setting 0/hysteresis {trigger_hysteresis:.3f}.")
    daq_module.set("hysteresis", trigger_hysteresis)
    # The number of times to trigger.
    trigger_count = int(num_pulses / 2)
    daq_module.set("count", trigger_count)
    daq_module.set("holdoff/count", 0)
    daq_module.set("holdoff/time", 0.100)
    trigger_delay = -0.020
    daq_module.set("delay", trigger_delay)
    demod_rate = daq.getDouble("/%s/demods/%d/rate" % (device, demod_index))
    # 'grid/mode' - Specify the interpolation method of
    #   the returned data samples.
    #
    # 1 = Nearest. If the interval between samples on the grid does not match
    #     the interval between samples sent from the device exactly, the nearest
    #     sample (in time) is taken.
    #
    # 2 = Linear interpolation. If the interval between samples on the grid does
    #     not match the interval between samples sent from the device exactly,
    #     linear interpolation is performed between the two neighbouring
    #     samples.
    #
    # 4 = Exact. The subscribed signal with the highest sampling rate (as sent
    #     from the device) defines the interval between samples on the DAQ
    #     Module's grid. If multiple signals are subscribed, these are
    #     interpolated onto the grid (defined by the signal with the highest
    #     rate, "highest_rate"). In this mode, duration is
    #     read-only and is defined as num_cols/highest_rate.
    daq_module.set("grid/mode", 4)
    # For an FFT the number of samples needs to be a binary power
    # sample_count = int(demod_rate * trigger_duration)
    sample_count = 2048
    # The duration (the length of time to record each time we trigger) must fit exactly with
    # the number of samples. Otherwise in exact mode, it will be adjusted to fit.
    trigger_duration = sample_count / demod_rate
    daq_module.set("duration", trigger_duration)
    daq_module.set("grid/cols", sample_count)
    trigger_duration = daq_module.getDouble("duration")
    # The size of the internal buffer used to record triggers (in seconds), this
    # should be larger than trigger_duration.
    buffer_size = daq_module.getInt("buffersize")

    # In this example we obtain the absolute values of the FFT of the quadrature components
    # (x+iy) of the recorded data.
    # This is done by appending the signal/operations to the basic node path using dot notation and
    # then subscribing to this path (signal).
    # We could additionally subscribe to other node paths.
    signal_path = "/%s/demods/%d/sample.xiy.fft.abs" % (device, demod_index)
    filter_compensations_path = "/%s/demods/%d/sample.xiy.fft.abs.filter" % (
        device,
        demod_index,
    )
    daq_module.subscribe(signal_path)
    daq_module.subscribe(filter_compensations_path)

    # Start the Data Acquisition's thread.
    daq_module.execute()
    time.sleep(2 * buffer_size)

    # Generate some pulses on the signal outputs by changing the signal output
    # mixer's amplitude. This is for demonstration only and is not necessary to
    # configure the module, we simply generate a signal upon which we can trigger.
    for _ in range(num_pulses):
        daq.setDouble(
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            sigouts_low * (1 + 0.05 * np.random.uniform(-1, 1, 1)[0]),
        )
        daq.sync()
        time.sleep(0.2)
        daq.setDouble(
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            sigouts_high * (1 + 0.05 * np.random.uniform(-1, 1, 1)[0]),
        )
        daq.sync()
        time.sleep(0.1)
        # Check and display the progress.
        progress = daq_module.progress()
        print(
            f"Data Acquisition Module progress (acquiring {trigger_count:d} triggers): \
                {progress[0]:.2%}.",
            end="\r",
        )
        # Check whether the Data Acquisition Module has finished.
        if daq_module.finished():
            print("\nTrigger is finished.")
            break
    print("")
    daq.setDouble(
        "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
        sigouts_low,
    )

    # Wait for the Data Acquisition's buffers to finish processing the triggers.
    time.sleep(2 * buffer_size)

    # Read the Data Acquisition's data, this command can also be executed before
    # daq_module.finished() is True. In that case data recorded up to that point in
    # time is returned and we would still need to issue read() at the end to
    # fetch the rest of the data.
    return_flat_data_dict = True
    data = daq_module.read(return_flat_data_dict)

    # Check that the dictionary returned is non-empty.
    assert (
        data
    ), "read() returned an empty data dictionary, did you subscribe to any paths?"
    # Note: data could be empty if no data arrived, e.g., if the demods were
    # disabled or had rate 0
    assert (
        signal_path in data
    ), f"no data recorded: data dictionary has no key `{signal_path}`."
    samples = data[signal_path]
    filter_compensations = data[filter_compensations_path]
    print(f"Data Acquisition's read() returned {len(samples)} signal segments.")
    assert (
        len(samples) == trigger_count
    ), f"Unexpected number of signal segments returned: `{len(samples)}`. \
        Expected: `{trigger_count}`."

    if plot and samples:

        _, axs = plt.subplots(2)
        # Plot the FFT bins returned by the Data Acquisition.
        for index, sample in enumerate(samples):
            filter_compensation = filter_compensations[index]
            bin_count = len(sample["value"][0])
            bin_resolution = sample["header"]["gridcoldelta"]
            frequencies = np.arange(bin_count)
            # Center frequency and bandwidth not yet implemented.
            # So we calculate from the gridcoldelta.
            bandwidth = bin_resolution * len(frequencies)
            frequencies = (
                frequencies * bin_resolution - bandwidth / 2.0 + bin_resolution / 2.0
            )
            amplitude_db = 20 * np.log10(sample["value"][0] * np.sqrt(2) / amplitude)
            amplitude_db_compensated = 20 * np.log10(
                (sample["value"][0] / filter_compensation["value"][0])
                * np.sqrt(2)
                / amplitude
            )
            axs[0].plot(frequencies, amplitude_db)
            axs[1].plot(frequencies, amplitude_db_compensated)
        axs[0].grid()
        title = f"Data Acquisition's read() returned {len(samples)} FFTs each with \
            {len(samples[0]['value'][0])} bins"
        axs[0].set_title(title)
        axs[0].set_xlabel("Frequency ($Hz$)")
        axs[0].set_ylabel("Amplitude R ($dBV$)")
        axs[0].set_autoscale_on(True)
        axs[1].grid()
        axs[1].set_xlabel("Frequency ($Hz$)")
        axs[1].set_ylabel("Amplitude R ($dBV$)(dBV)\n with Demod Filter Compensation")
        axs[1].set_autoscale_on(True)

        plt.show()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
