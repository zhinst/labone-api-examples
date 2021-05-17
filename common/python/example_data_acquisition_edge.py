# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Python API Example for the Data Acquisition Core Module. This
example demonstrates how to obtain bursts of demodulator data when a
demodulator's R value is larger than a specified threshold using an edge
trigger.

The Data Acquisition Module implements software triggering which operates
analogously to the types of triggering found in laboratory oscilloscopes. The
Data Acquisition Module has a non-blocking (asynchronous) interface, it starts it's
own thread to communicate with the data server.

Note:
This example requires a feedback cable between Signal Output 1 and Signal
Input 1 and changes the signal output's amplitude in order to create a signal
upon which to trigger.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_data_acquisition_edge.py [options] <device_id>
    example_data_acquisition_edge.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help                 Show this screen.
    -a --amplitude AMPLITUDE  The amplitude to set on the signal output. [default: 0.25]
    -r --repetitions NUM      The value of the DAQ module parameter grid/repetitions to use;
                              if repetitions=n is greater than 1, the data is averaged
                              n times. [default: 1]
    -s --save                 saves the data to file
    -p --plot                 create a plot.

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


def run_example(
    device_id: str,
    amplitude: float = 0.25,
    repetitions: int = 1,
    save: bool = False,
    plot: bool = False,
):
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

    daq.setDebugLevel(0)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all device configurations. The values below may be
    # changed if the instrument has multiple input/output channels and/or either
    # the Multifrequency or Multidemodulator options installed.
    out_channel = 0
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(props, out_channel)
    in_channel = 0
    demod_index = 0
    osc_index = 0
    demod_rate = 10e3
    time_constant = 0.01
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
    timeconstant_set = daq.getDouble(
        "/%s/demods/%d/timeconstant" % (device, demod_index)
    )
    time.sleep(10 * timeconstant_set)

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
    print(f"Setting hysteresis {trigger_hysteresis:.3f}.")
    daq_module.set("hysteresis", trigger_hysteresis)
    # Set the number of repetitions for the averaging
    daq_module.set("grid/repetitions", repetitions)
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
    # The length of time to record each time we trigger
    trigger_duration = 0.18
    daq_module.set("duration", trigger_duration)
    # To keep our desired duration we must calculate the number of samples so that it
    # fits with the demod sampling rate. Otherwise in exact mode, it will be adjusted to fit.
    sample_count = int(demod_rate * trigger_duration)
    daq_module.set("grid/cols", sample_count)
    trigger_duration = daq_module.getDouble("duration")
    buffer_size = daq_module.getInt("buffersize")

    # We subscribe to the same demodulator sample we're triggering on, but we
    # could additionally subscribe to other node paths.
    signal_path = "/%s/demods/%d/sample.r" % (device, demod_index)
    if repetitions > 1:
        signal_path += ".avg"
    daq_module.subscribe(signal_path)

    # Set the filename stem for saving the data to file. The data are saved in a separate
    # numerically incrementing sub-directory prefixed with the /save/filename value each
    # time a save command is issued.
    # The base directory is specified with the save/directory parameter. The default is
    # C:\Users\richardc\Documents\Zurich Instruments\LabOne\WebServer on Windows.
    # On linux $HOME/Zurich Instruments/LabOne/WebServer
    daq_module.set("save/filename", "sw_trigger_with_save")
    # Set the file format to use.
    # 0 = MATLAB, 1 = CSV, 3 = SXM image format (for 2D acquisitions), 4 = HDF5
    # daq_module.set("save/fileformat", 4)
    # Alternatively you can pass one of the strings "mat", "csv", "sxm" or "hdf5"
    # to the set command.
    daq_module.set("save/fileformat", "hdf5")

    # Start the Data Acquisition Module running.
    daq_module.execute()
    time.sleep(1.2 * buffer_size)

    # Generate some pulses on the signal outputs by changing the signal output
    # mixer's amplitude. This is for demonstration only and is not necessary to
    # configure the module, we simply generate a signal upon which we can trigger.
    for _ in range(num_pulses * repetitions):
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
    time.sleep(1.2 * buffer_size)

    if save:
        # Indicate that the data should be saved to file.
        # This must be done before the read() command.
        # Otherwise there is no longer any data to save.
        daq_module.set("save/save", save)

    # Read the Data Acquisition's data, this command can also be executed before
    # daq_module.finished() is True. In that case data recorded up to that point in
    # time is returned and we would still need to issue read() at the end to
    # fetch the rest of the data.
    return_flat_data_dict = True
    data = daq_module.read(return_flat_data_dict)

    if save:
        # Wait until the save is complete. The saving is done asynchronously in the background
        # so we need to check it's finished before exiting.
        save_done = daq_module.getInt("save/save")
        while save_done != 0:
            save_done = daq_module.getInt("save/save")

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
    print(f"Data Acquisition's read() returned {len(samples)} signal segments.")
    assert (
        len(samples) == trigger_count
    ), f"Unexpected number of signal segments returned: `{len(samples)}`. \
        Expected: `{trigger_count}`."

    # Get the sampling rate of the device's ADCs, the device clockbase.
    clockbase = float(daq.getInt("/%s/clockbase" % device))
    # Use the clockbase to calculate the duration of the first signal segment's
    # demodulator data, the segments are accessed by indexing `samples`.
    dt_seconds = (
        samples[0]["timestamp"][0][-1] - samples[0]["timestamp"][0][0]
    ) / clockbase
    print(
        f"The first signal segment contains {dt_seconds:.3f} seconds of demodulator data."
    )
    np.testing.assert_almost_equal(
        dt_seconds,
        trigger_duration,
        decimal=2,
        err_msg="Duration of demod data in first signal segment does \
            not match the expected duration.",
    )

    if plot and samples:

        _, axis = plt.subplots()

        # Plot some relevant Data Acquisition parameters.
        axis.axvline(0.0, linewidth=2, linestyle="--", color="k", label="Trigger time")
        axis.axvline(
            trigger_delay, linewidth=2, linestyle="--", color="grey", label="delay"
        )
        axis.axvline(
            trigger_duration + trigger_delay,
            linewidth=2,
            linestyle=":",
            color="k",
            label="duration + delay",
        )
        axis.axhline(
            trigger_level, linewidth=2, linestyle="-", color="k", label="level"
        )
        axis.axhline(
            trigger_level - trigger_hysteresis,
            linewidth=2,
            linestyle="-.",
            color="k",
            label="hysteresis",
        )
        axis.axvspan(
            trigger_delay, trigger_duration + trigger_delay, alpha=0.2, color="grey"
        )
        axis.axhspan(
            trigger_level, trigger_level - trigger_hysteresis, alpha=0.5, color="grey"
        )
        # Plot the signal segments returned by the Data Acquisition.
        for sample in samples:
            # Align the triggers using their trigger timestamps which are stored in the chunk
            # header "changed" timestamp. This is the timestamp of the last acquired trigger.
            # Note that with the new software trigger, the trigger timestamp has the trigger offset
            # added to it, so we need to subtract it to get the sample and trigger timestamps to
            # align.
            trigger_ts = sample["header"]["changedtimestamp"] - int(
                sample["header"]["gridcoloffset"] * clockbase
            )
            t = (sample["timestamp"] - float(trigger_ts)) / clockbase
            axis.plot(t[0], sample["value"][0])
        axis.grid()
        title = (
            f"The Data Acquisition Module returned {len(samples)} segments of demodulator data\n"
            f"each with a duration of {trigger_duration:.3f} seconds"
        )
        axis.set_title(title)
        axis.set_xlabel("Time, relative to the trigger time ($s$)")
        axis.set_ylabel(r"Demodulator R ($V_\mathrm{RMS}$)")
        axis.set_ylim([round(0.5 * amplitude, 2), round(1.5 * amplitude, 2)])
        handles, labels = axis.get_legend_handles_labels()
        axis.legend(handles, labels, fontsize="small")

        plt.show()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
