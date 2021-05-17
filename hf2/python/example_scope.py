# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example.

Demonstrate how to connect to a HF2 Zurich Instruments Lock-in Amplifier and
obtain scope data using the Scope Module.

Connect to a Zurich Instruments Lock-in Amplifier via the Data Server, generate
a sine wave on the signal outputs and obtain the waveform from the signal outputs
sing the Scope Module. The specified min_num_records of scope records are obtained
from the device with and without enabling the scope's trigger.

Note:
This is an HF2 example and uses API level 1; users of other device
classes are recommended to connect via API level 6, particularly when
obtaining scope data.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x HF2 Instrument
    * Signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_awg_sourcefile.py [options] <device_id>
    example_awg_sourcefile.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: HF2]

Options:
    -h --help                    Show this screen.
    -p --plot                    create a plot.
    -i --inputselect INPUT       The input signal to measure with the
                                 scope (/dev..../scopes/0/channels/0/inputselect):
                                     0 - signal input 0,
                                     1 - signal input 1,
                                     2 - signal output 0,
                                     3 - signal output 1.
                                 [default: 0]
    -a --amplitude VALUE         The amplitude of the signal to configure on the
                                 signal output. [default: 0.1]
    -r --output_range RANGE      The range to use on the signal output. [default: 1]
    -w --averaging_weight VALUE  Value to use for the averager/weight parameter.
                                 [default: 1]
    --historylength LENGTH       Value to use for the historylength parameter,
                                 the Scope Module will only return this number of
                                 scope records. [default: 20]
    -r --min_num_records NUM     Specify the minimum number of scope records to
                                 acquire. min_num_records can be set to a value
                                 greater than historylength in order to allow the
                                 averager to settle - only the last historylength
                                 records will be returned. [default: 20]

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
      Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
      sub-folder.
"""

import time
import warnings
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt
from matplotlib import cm


def run_example(
    device_id: str,
    plot: bool = False,
    inputselect: int = 0,
    amplitude: float = 0.1,
    output_range: float = 1.0,
    averaging_weight: int = 1,
    historylength: int = 20,
    min_num_records: int = 20,
):
    """run the example."""

    # The API level supported by this example. Note, the HF2 data server
    # only supports API Level 1.
    apilevel_example = 1
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    err_msg = "This example only supports HF2 Instruments."
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id, apilevel_example, required_devtype="HF2", required_err_msg=err_msg
    )
    zhinst.utils.api_server_version_check(daq)

    # Enable the API's log.
    daq.setDebugLevel(3)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment.

    # Determine the sigin/sigout channels to configure based on the specified scope inputselect.
    if inputselect in [0, 2]:
        # inputselect 0 corresponds to signal input 1
        out_channel = 0
        in_channel = 0
    elif inputselect in [1, 3]:
        # inputselect 0 corresponds to signal input 2
        out_channel = 1
        in_channel = 1
    else:
        raise Exception(
            "This example only supports signal inputs and outputs; it does not support scope "
            f"inputselect {inputselect}. Use 0, 1, 2 or 3 instead."
        )

    # Get the value of the instrument's default Signal Output mixer channel.
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(
        props, output_channel=out_channel
    )

    osc_index = 0
    demod_index = 0
    frequency = 1e6
    exp_setting = [
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        ["/%s/sigins/%d/range" % (device, in_channel), 2 * amplitude],
        ["/%s/sigins/%d/diff" % (device, in_channel), 0],
        ["/%s/sigouts/%d/add" % (device, out_channel), 0],
        ["/%s/demods/%d/oscselect" % (device, demod_index), osc_index],
        ["/%s/demods/%d/harmonic" % (device, demod_index), 1],
        ["/%s/oscs/%d/freq" % (device, osc_index), frequency],
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), output_range],
        [
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            amplitude / output_range,
        ],
    ]
    daq.set(exp_setting)

    ################################################################################################
    # Configure the scope and obtain data with triggering disabled.
    ################################################################################################
    # The settings for the scope.
    #
    # The scope's sampling rate is configured by specifying the ``time`` node
    # (/devN/scopes/0/time). The rate is equal to 210e6/2**time, where 210e6 is
    # the HF2 ADC's sampling rate (whose value can be read from the device's
    # clockbase node, /devX/clockbase). ``time`` is an integer in range(0,16).
    #
    # Since the length of a scope record is fixed (2048) on an HF2, specifying the
    # rate also specifies the time duration of a scope record,
    # t_shot=2048*1./rate=2048*2**time/210e6.
    #
    # Therefore, if we would like to obtain (at least) 10 periods of the signal
    # generated by Oscillator 1, we need to set the scope's time parameter as
    # following:
    clockbase = float(daq.getInt("/%s/clockbase" % device))  # 210e6 for HF2
    desired_t_shot = 10.0 / frequency
    scope_time = np.ceil(np.max([0, np.log2(clockbase * desired_t_shot / 2048.0)]))
    if scope_time > 15:
        scope_time = 15
        warnings.warn(
            "Can't not obtain scope durations of %.3f s, scope record duration will be %.3f."
            % (desired_t_shot, 2048.0 * 2 ** scope_time / clockbase)
        )
    print("Will set /%s/scopes/0/time to %d." % (device, scope_time))

    scope_settings = [
        ["/%s/scopes/0/channel" % (device), inputselect],
        ["/%s/scopes/0/trigchannel" % (device), -1],
        ["/%s/scopes/0/trigholdoff" % (device), 0.1],
        # Enable bandwidth limiting: avoid antialiasing effects due to
        # sub-sampling when the scope sample rate is less than the input
        # channel's sample rate.
        ["/%s/scopes/0/bwlimit" % (device), 1],
        # Set the sampling rate.
        ["/%s/scopes/0/time" % (device), scope_time],
        # Enable the scope
        ["/%s/scopes/0/enable" % device, 1],
    ]
    daq.set(scope_settings)

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
    scopeModule.set("averager/weight", averaging_weight)
    # 'historylength' : The number of scope records to keep in the Scope Module's memory, when more
    #  records arrive in the Module from the device the oldest records are overwritten.
    scopeModule.set("historylength", historylength)

    scope_channel_lookup = {0: "sigin0", 1: "sigin1", 2: "sigout0", 3: "sigout1"}
    scope_channel = scope_channel_lookup[inputselect]
    if scope_channel == "sigin0":
        externalscaling = daq.getDouble(f"/{device}/sigins/0/range")
    elif scope_channel == "sigin1":
        externalscaling = daq.getDouble(f"/{device}/sigins/1/range")
    elif scope_channel == "sigout0":
        externalscaling = daq.getDouble(f"/{device}/sigouts/0/range")
    elif scope_channel == "sigout1":
        externalscaling = daq.getDouble(f"/{device}/sigouts/1/range")
    scopeModule.set("externalscaling", externalscaling)

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

    # Modify the scope settings to enable triggering. Trigger on the same channel we're recording.
    scope_settings = [
        ["/%s/scopes/0/trigchannel" % (device), inputselect],
        ["/%s/scopes/0/triglevel" % (device), 0.0],
        ["/%s/scopes/0/trigholdoff" % (device), 0.1],
    ]
    daq.set(scope_settings)

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
    # Configure the Scope Module to obtain FFT data
    ################################################################################################

    # Set the Scope Module's mode to return frequency domain data.
    scopeModule.set("mode", 3)
    # Use a Hann window function.
    scopeModule.set("fft/window", 1)

    # Get the instrument's ADC sampling rate - used to plot the Scope's FFT.
    clockbase = daq.getInt(f"/{device}/clockbase")

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

        def plot_scope_records(plot_axes, scope_records, scope_time=0):
            """
            Helper function to plot scope records.
            """
            axis = plot_axes
            # The HF2 only has one scope channel.
            scope_input_channel = 0
            colors = cm.rainbow(np.linspace(0, 1, len(scope_records)))
            for index, record in enumerate(scope_records):
                totalsamples = record[0]["totalsamples"]
                wave = record[0]["wave"][scope_input_channel, :]
                if record[0]["flags"] & 7:
                    print(
                        "Skipping plot of record ",
                        index,
                        ": record flags=",
                        record[0]["flags"],
                        "indicate corrupt data.",
                    )
                    continue
                if not record[0]["channelmath"][scope_input_channel] & 2:
                    # We're in time mode: Create a time array relative to the trigger time.
                    dt = record[0]["dt"]
                    # Note, triggertimestamp and the timestamp always have the same value on HF2.
                    t = np.arange(0, totalsamples) * dt
                    axis.plot(1e6 * t, wave, color=colors[index])
                elif record[0]["channelmath"][scope_input_channel] & 2:
                    # We're in FFT mode.
                    scope_rate = clockbase / 2 ** scope_time
                    f = np.linspace(0, scope_rate / 2, totalsamples)
                    axis.semilogy(f / 1e6, wave, color=colors[index])
            plt.draw()
            axis.grid(True)
            axis.set_ylabel("Amplitude [V]")
            axis.autoscale(enable=True, axis="x", tight=True)

        # Plot the scope data with triggering disabled.
        _, (ax1, ax2) = plt.subplots(2)

        plot_scope_records(ax1, data_no_trig[wave_nodepath])
        ax1.set_title(
            f"{len(data_no_trig[wave_nodepath])} Scope records from {device} (triggering disabled)"
        )

        # Plot the scope data with triggering enabled.
        plot_scope_records(ax2, data_with_trig[wave_nodepath])
        ax2.axvline(0.0, linewidth=2, linestyle="--", color="k", label="Trigger time")
        ax2.set_title(
            f"{len(data_with_trig[wave_nodepath])} Scope records from {device} (triggering enabled)"
        )
        ax2.set_xlabel("t (relative to trigger) [us]")
        plt.show()

        # Plot the FFT of the scope data.
        _, axis = plt.subplots()
        plot_scope_records(axis, data_fft[wave_nodepath], scope_time)
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
                f"\nScope Module did not return {num_records} records after {timeout} s - forcing \
                    stop."
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
                f"Warning: Scope record {index}/{num_records} indicates transfer failure (corrupt \
                    data)."
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
