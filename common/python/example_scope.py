# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example.

Demonstrate how to connect to a Zurich Instruments Device and obtain scope data
from two scope channels using the Scope Module.

Connect to a Zurich Instruments Device via the Data Server,
generate a sine wave on the signal outputs and obtain the waveform from the
signal inputs using the Scope Module. The specified min_num_records of scope
records are obtained from the device with and without enabling the scope's
trigger.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x MF or UHF Instrument with DIG Option (HF2 does not support
            multi-channel recording).

Usage:
    example_scope.py [options] <device_id>
    example_scope.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: UHFLI(DIG)|MF.*(DIG)]

Options:
    -h --help                   Show this screen.
    --no-plot                   Hide plot of the recorded data.
    -i --inputselect INPUT      The input signal to measure with the
                                scope (/dev..../scopes/0/channels/0/inputselect):
                                    0 - signal input 0,
                                    1 - signal input 1,
                                    2 - signal output 0,
                                    3 - signal output 1.
                                [default: 0]
    -l --scope_length  LENGTH   The length of the scope segment(s) to record
                                (/dev..../scopes/0/length). [default: 4096]
    -t --trigholdoff TIME       The scope hold-off time (s). [default: 0.05]
    -a --amplitude VALUE        The amplitude of the signal to configure on the
                                signal output. [default: 0.5]
    -r --output_range RANGE     The range to use on the signal output. [default: 1.5]
    -w --averager_weight VALUE  Value to use for the averager/weight parameter.
                                [default: 1]
    --historylength LENGTH      Value to use for the historylength parameter,
                                the Scope Module will only return this number of
                                scope records. [default: 20]
    -r --min_num_records NUM    Specify the minimum number of scope records to
                                acquire. min_num_records can be set to a value
                                greater than historylength in order to allow the
                                averager to settle - only the last historylength
                                records will be returned. [default: 20]

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
    Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
    sub-folder.
"""

import time
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt
from matplotlib import cm


def run_example(
    device_id: str,
    plot: bool = True,
    inputselect: int = 0,
    scope_length: int = 2 ** 12,
    trigholdoff: float = 0.050,
    amplitude: float = 0.5,
    output_range: float = 1.5,
    averager_weight: int = 1,
    historylength: int = 20,
    min_num_records: int = 20,
):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    # This example can't run with HF2 Instruments.
    required_devtype = r"UHF|MF"  # Regular expression of supported instruments.
    required_options = {}  # No special options required.
    required_err_msg = (
        "This example is only compatible with UHF and MF Instruments: "
        "The HF2 Data Server does not support API Levels > 1, which "
        "is required to use the extended scope data structure. "
        "For HF2, see the example zhinst.examples.hf2.example_scope."
    )
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id,
        apilevel_example,
        required_devtype=required_devtype,
        required_options=required_options,
        required_err_msg=required_err_msg,
    )
    zhinst.utils.api_server_version_check(daq)

    # Enable the API's log.
    daq.setDebugLevel(3)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment.

    # Determine the sigin/sigout channels to configure based on the specified scope inputselect.
    if inputselect == 0:
        # inputselect 0 corresponds to signal input 1
        out_channel = 0
        in_channel = 0
    elif inputselect == 1:
        # inputselect 0 corresponds to signal input 2
        out_channel = 1
        in_channel = 1
    else:
        raise Exception(
            f"This example only supports signal inputs; it does not support scope inputselect \
                {inputselect}. "
            "Use 0 or 1 instead."
        )

    # Get the value of the instrument's default Signal Output mixer channel.
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(
        props, output_channel=out_channel
    )

    osc_index = 0
    scope_in_channel = 0  # scope input channel
    if props["devicetype"].startswith("UHF"):
        frequency = 10.0e6
    else:
        frequency = 400e3
    exp_setting = [
        # The output signal.
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), output_range],
        [
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            amplitude,
        ],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
        ["/%s/sigins/%d/imp50" % (device, in_channel), 1],
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        # We will use autorange to adjust the sigins range.
        # ['/%s/sigins/%d/range'           % (device, in_channel), 2*amplitude],
        ["/%s/oscs/%d/freq" % (device, osc_index), frequency],
    ]
    node_branches = daq.listNodes(f"/{device}/", 0)
    if "DEMODS" in node_branches:
        # NOTE we don't need any demodulator data for this example, but we need
        # to configure the frequency of the output signal on out_mixer_c.
        exp_setting.append(
            ["/%s/demods/%d/oscselect" % (device, out_mixer_channel), osc_index]
        )
    daq.set(exp_setting)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that the signal input and output configuration has taken effect
    # before calculating the signal input autorange.
    daq.sync()

    # Perform an automatic adjustment of the signal inputs range based on the
    # measured input signal's amplitude measured over approximately 100 ms.
    # This is important to obtain the best bit resolution on the signal inputs
    # of the measured signal in the scope.
    zhinst.utils.sigin_autorange(daq, device, in_channel)

    ################################################################################################
    # Configure the scope and obtain data with triggering disabled.
    ################################################################################################

    # Configure the instrument's scope via the /devx/scopes/0/ node tree branch.
    # 'length' : the length of each segment
    daq.setInt("/%s/scopes/0/length" % device, scope_length)
    # 'channel' : select the scope channel(s) to enable.
    #  Bit-encoded as following:
    #   1 - enable scope channel 0
    #   2 - enable scope channel 1
    #   3 - enable both scope channels (requires DIG option)
    # NOTE we are only interested in one scope channel: scope_in_channel and leave
    # the other channel unconfigured
    daq.setInt("/%s/scopes/0/channel" % device, 1)
    # 'channels/0/bwlimit' : bandwidth limit the scope data. Enabling bandwidth
    # limiting avoids antialiasing effects due to subsampling when the scope
    # sample rate is less than the input channel's sample rate.
    #  Bool:
    #   0 - do not bandwidth limit
    #   1 - bandwidth limit
    daq.setInt("/%s/scopes/0/channels/%d/bwlimit" % (device, scope_in_channel), 1)
    # 'channels/0/inputselect' : the input channel for the scope:
    #   0 - signal input 1
    #   1 - signal input 2
    #   2, 3 - trigger 1, 2 (front)
    #   8-9 - auxiliary inputs 1-2
    #   The following inputs are additionally available with the DIG option:
    #   10-11 - oscillator phase from demodulator 3-7
    #   16-23 - demodulator 0-7 x value
    #   32-39 - demodulator 0-7 y value
    #   48-55 - demodulator 0-7 R value
    #   64-71 - demodulator 0-7 Phi value
    #   80-83 - pid 0-3 out value
    #   96-97 - boxcar 0-1
    #   112-113 - cartesian arithmetic unit 0-1
    #   128-129 - polar arithmetic unit 0-1
    #   144-147 - pid 0-3 shift value
    daq.setInt(
        "/%s/scopes/0/channels/%d/inputselect" % (device, scope_in_channel), inputselect
    )
    # 'time' : timescale of the wave, sets the sampling rate to clockbase/2**time.
    #   0 - sets the sampling rate to 1.8 GHz
    #   1 - sets the sampling rate to 900 MHz
    #   ...
    #   16 - sets the samptling rate to 27.5 kHz
    scope_time = 0
    daq.setInt("/%s/scopes/0/time" % device, scope_time)
    # 'single' : only get a single scope record.
    #   0 - acquire continuous records
    #   1 - acquire a single record
    daq.setInt("/%s/scopes/0/single" % device, 0)
    # 'trigenable' : enable the scope's trigger (boolean).
    #   0 - acquire continuous records
    #   1 - only acquire a record when a trigger arrives
    daq.setInt("/%s/scopes/0/trigenable" % device, 0)
    # 'trigholdoff' : the scope hold off time inbetween acquiring triggers
    #                 (still relevant if triggering is disabled).
    daq.setDouble("/%s/scopes/0/trigholdoff" % device, trigholdoff)
    # 'segments/enable' : Disable segmented data recording.
    daq.setInt("/%s/scopes/0/segments/enable" % device, 0)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that the settings have taken effect on the device before acquiring
    # data.
    daq.sync()

    # Now initialize and configure the Scope Module.
    scopeModule = daq.scopeModule()
    # 'mode' : Scope data processing mode.
    # 0 - Pass through scope segments assembled, returned unprocessed, non-interleaved.
    # 1 - Moving average, scope recording assembled, scaling applied, averaged, if averaging is
    #     enabled.
    # 2 - Not yet supported.
    # 3 - As for mode 1, except an FFT is applied to every segment of the scope recording.
    scopeModule.set("mode", 1)
    # 'averager/weight' : Averager behaviour.
    #   weight=1 - don't average.
    #   weight>1 - average the scope record shots using an exponentially weighted moving average.
    scopeModule.set("averager/weight", averager_weight)
    # 'historylength' : The number of scope records to keep in the Scope Module's memory, when more
    #                   records arrive in the Module from the device the oldest records are
    #                   overwritten.
    scopeModule.set("historylength", historylength)

    # Subscribe to the scope's data in the module.
    wave_nodepath = f"/{device}/scopes/0/wave"
    scopeModule.subscribe(wave_nodepath)

    # Enable the scope and read the scope data arriving from the device.
    data_no_trig = get_scope_records(device, daq, scopeModule, min_num_records)
    assert (
        wave_nodepath in data_no_trig
    ), f"The Scope Module did not return data for {wave_nodepath}."
    print(
        f"Number of scope records with triggering disabled: {len(data_no_trig[wave_nodepath])}."
    )
    check_scope_record_flags(data_no_trig[wave_nodepath])

    ################################################################################################
    # Configure the scope and obtain data with triggering enabled.
    ################################################################################################

    # Now configure the scope's trigger to get aligned data
    # 'trigenable' : enable the scope's trigger (boolean).
    #   0 - acquire continuous records
    #   1 - only acquire a record when a trigger arrives
    daq.setInt("/%s/scopes/0/trigenable" % device, 1)

    # Specify the trigger channel, we choose the same as the scope input
    daq.setInt("/%s/scopes/0/trigchannel" % device, in_channel)

    # Trigger on rising edge?
    daq.setInt("/%s/scopes/0/trigrising" % device, 1)

    # Trigger on falling edge?
    daq.setInt("/%s/scopes/0/trigfalling" % device, 0)

    # Set the trigger threshold level.
    daq.setDouble("/%s/scopes/0/triglevel" % device, 0.00)

    # Set hysteresis triggering threshold to avoid triggering on noise
    # 'trighysteresis/mode' :
    #  0 - absolute, use an absolute value ('scopes/0/trighysteresis/absolute')
    #  1 - relative, use a relative value ('scopes/0trighysteresis/relative') of the trigchannel's
    #      input range (0.1=10%).
    daq.setDouble("/%s/scopes/0/trighysteresis/mode" % device, 1)
    daq.setDouble("/%s/scopes/0/trighysteresis/relative" % device, 0.1)  # 0.1=10%

    # Set the trigger hold-off mode of the scope. After recording a trigger event, this specifies
    # when the scope should become re-armed and ready to trigger, 'trigholdoffmode':
    #  0 - specify a hold-off time between triggers in seconds ('scopes/0/trigholdoff'),
    #  1 - specify a number of trigger events before re-arming the scope ready to trigger
    #      ('scopes/0/trigholdcount').
    daq.setInt("/%s/scopes/0/trigholdoffmode" % device, 0)
    daq.setDouble("/%s/scopes/0/trigholdoff" % device, trigholdoff)

    # The trigger reference position relative within the wave, a value of 0.5 corresponds to the
    # center of the wave.
    daq.setDouble("/%s/scopes/0/trigreference" % device, 0.25)

    # Set trigdelay to 0.: Start recording from when the trigger is activated.
    daq.setDouble("/%s/scopes/0/trigdelay" % device, 0.0)

    # Disable trigger gating.
    daq.setInt("/%s/scopes/0/triggate/enable" % device, 0)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that the settings have taken effect on the device before acquiring
    # data.
    daq.sync()

    # Enable the scope and read the scope data arriving from the device. Note: The module is already
    # configured and the required data is already subscribed from above.
    data_with_trig = get_scope_records(device, daq, scopeModule, min_num_records)

    assert (
        wave_nodepath in data_with_trig
    ), f"The Scope Module did not return data for {wave_nodepath}."
    print(
        f"Number of scope records returned with triggering enabled: \
            {len(data_with_trig[wave_nodepath])}."
    )
    check_scope_record_flags(data_with_trig[wave_nodepath])

    ################################################################################################
    # Configure the Scope Module to calculate FFT data
    ################################################################################################

    # Set the Scope Module's mode to return frequency domain data.
    scopeModule.set("mode", 3)
    # Use a Hann window function.
    scopeModule.set("fft/window", 1)

    # Enable the scope and read the scope data arriving from the device; the Scope Module will
    # additionally perform an FFT on the data. Note: The other module parameters are already
    # configured and the required data is already subscribed from above.
    data_fft = get_scope_records(device, daq, scopeModule, min_num_records)
    assert (
        wave_nodepath in data_fft
    ), f"The Scope Module did not return data for {wave_nodepath}."
    print(
        f"Number of scope records returned with triggering enabled (and FFT'd): \
            {len(data_fft[wave_nodepath])}."
    )
    check_scope_record_flags(data_fft[wave_nodepath])

    if plot:

        # Get the instrument's ADC sampling rate.
        clockbase = daq.getInt(f"/{device}/clockbase")

        def plot_scope_records(
            plot_axes, scope_records, scope_input_channel, scope_time=0
        ):
            """
            Helper function to plot scope records.
            """
            axis = plot_axes
            colors = cm.rainbow(np.linspace(0, 1, len(scope_records)))
            for index, record in enumerate(scope_records):
                totalsamples = record[0]["totalsamples"]
                wave = record[0]["wave"][scope_input_channel, :]
                if record[0]["flags"] & 7:
                    print(
                        f"Skipping plot of record {index}: record flags={record[0]['flags']} \
                            indicate corrupt data."
                    )
                    continue
                if not record[0]["channelmath"][scope_input_channel] & 2:
                    # We're in time mode: Create a time array relative to the trigger time.
                    dt = record[0]["dt"]
                    # The timestamp is the timestamp of the last sample in the scope segment.
                    timestamp = record[0]["timestamp"]
                    triggertimestamp = record[0]["triggertimestamp"]
                    t = np.arange(-totalsamples, 0) * dt + (
                        timestamp - triggertimestamp
                    ) / float(clockbase)
                    axis.plot(1e6 * t, wave, color=colors[index])
                elif record[0]["channelmath"][scope_input_channel] & 2:
                    # We're in FFT mode.
                    scope_rate = clockbase / 2 ** scope_time
                    freq = np.linspace(0, scope_rate / 2, totalsamples)
                    axis.semilogy(freq / 1e6, wave, color=colors[index])
            plt.draw()
            axis.grid(True)
            axis.set_ylabel("Amplitude [V]")
            axis.autoscale(enable=True, axis="x", tight=True)

        # Plot the scope data with triggering disabled.
        _, (ax1, ax2) = plt.subplots(2)

        plot_scope_records(ax1, data_no_trig[wave_nodepath], scope_in_channel)
        ax1.set_title(
            f"{len(data_no_trig[wave_nodepath])} Scope records from {device} (triggering disabled)"
        )

        # Plot the scope data with triggering enabled.
        plot_scope_records(ax2, data_with_trig[wave_nodepath], scope_in_channel)
        ax2.axvline(0.0, linewidth=2, linestyle="--", color="k", label="Trigger time")
        ax2.set_title(
            f"{len(data_with_trig[wave_nodepath])} Scope records from {device} (triggering enabled)"
        )
        ax2.set_xlabel("t (relative to trigger) [us]")
        plt.show()

        # Plot the FFT of the scope data.
        _, axis = plt.subplots()
        plot_scope_records(axis, data_fft[wave_nodepath], scope_in_channel, scope_time)
        axis.set_title(
            f"FFT of {len(data_fft[wave_nodepath])} scope records from {device}"
        )
        axis.set_xlabel("f [MHz]")


def get_scope_records(device, daq, scopeModule, num_records=1):
    """
    Obtain scope records from the device using an instance of the Scope Module.
    """

    # Tell the module to be ready to acquire data; reset the module's progress to 0.0.
    scopeModule.execute()

    # Enable the scope: Now the scope is ready to record data upon receiving triggers.
    daq.setInt("/%s/scopes/0/enable" % device, 1)
    daq.sync()

    start = time.time()
    timeout = 30  # [s]
    records = 0
    progress = 0
    # Wait until the Scope Module has received and processed the desired number of records.
    while (records < num_records) or (progress < 1.0):
        time.sleep(0.5)
        records = scopeModule.getInt("records")
        progress = scopeModule.progress()[0]
        print(
            f"Scope module has acquired {records} records (requested {num_records}). "
            f"Progress of current segment {100.0 * progress}%.",
            end="\r",
        )
        # Advanced use: It's possible to read-out data before all records have been recorded (or
        # even before all segments in a multi-segment record have been recorded). Note that complete
        # records are removed from the Scope Module and can not be read out again; the read-out data
        # must be managed by the client code. If a multi-segment record is read-out before all
        # segments have been recorded, the wave data has the same size as the complete data and
        # scope data points currently unacquired segments are equal to 0.
        #
        # data = scopeModule.read(True)
        # wave_nodepath = f"/{device}/scopes/0/wave"
        # if wave_nodepath in data:
        #   Do something with the data...
        if (time.time() - start) > timeout:
            # Break out of the loop if for some reason we're no longer receiving scope data from the
            # device.
            print(
                f"\nScope Module did not return {num_records} records after {timeout} s - \
                    forcing stop."
            )
            break
    print("")
    daq.setInt("/%s/scopes/0/enable" % device, 0)

    # Read out the scope data from the module.
    data = scopeModule.read(True)

    # Stop the module; to use it again we need to call execute().
    scopeModule.finish()

    return data


def check_scope_record_flags(scope_records):
    """
    Loop over all records and print a warning to the console if an error bit in
    flags has been set.

    Warning: This function is intended as a helper function for the API's
    examples and it's signature or implementation may change in future releases.
    """
    num_records = len(scope_records)
    for index, record in enumerate(scope_records):
        if record[0]["flags"] & 1:
            print(
                f"Warning: Scope record {index}/{num_records} flag indicates dataloss."
            )
        if record[0]["flags"] & 2:
            print(
                f"Warning: Scope record {index}/{num_records} indicates missed trigger."
            )
        if record[0]["flags"] & 4:
            print(
                f"Warning: Scope record {index}/{num_records} indicates transfer failure \
                    (corrupt data)."
            )
        totalsamples = record[0]["totalsamples"]
        for wave in record[0]["wave"]:
            # Check that the wave in each scope channel contains the expected number of samples.
            assert (
                len(wave) == totalsamples
            ), f"Scope record {index}/{num_records} size does not match totalsamples."


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
