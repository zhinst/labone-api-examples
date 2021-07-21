# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to obtain demodulator data using ziDAQServer's blocking
(synchronous) poll() command.

This example demonstrates that whilst poll() does indeed block for the specified
recording duration, it will not only return the data during the recording
duration, but also data accumulated since subscribing (before poll was
called). In other words, subscribed data is buffered by the data server and API
(for a limited time) and this buffered data will also be returned by poll().

Connect to the device specified by device_id and obtain demodulator data using
ziDAQServer's blocking (synchronous) poll() command.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_poll.py [options] <device_id>
    example_poll.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help                 Show this screen.
    -a --amplitude AMPLITUDE  The amplitude to set on the signal output. [default: 0.5]
    --no-plot                 Hide plot of the recorded data.

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


def run_example(device_id: str, amplitude: float = 0.5, plot: bool = True):
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
    demod_rate = 1e3
    time_constant = 0.01
    frequency = 400e3
    exp_setting = [
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        ["/%s/sigins/%d/range" % (device, in_channel), 2 * amplitude],
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

    # Unsubscribe any streaming data.
    daq.unsubscribe("*")

    # Wait for the demodulator filter to settle.
    time.sleep(10 * time_constant)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that 1. the settings have taken effect on the device before issuing
    # the poll() command and 2. clear the API's data buffers. Note: the sync()
    # must be issued after waiting for the demodulator filter to settle above.
    daq.sync()

    # Subscribe to the demodulator's sample node path.
    path = "/%s/demods/%d/sample" % (device, demod_index)
    daq.subscribe(path)

    # Sleep for demonstration purposes: Allow data to accumulate in the data
    # server's buffers for one second: poll() will not only return the data
    # accumulated during the specified poll_length, but also for data
    # accumulated since the subscribe() or the previous poll.
    sleep_length = 1.0
    # For demonstration only: We could, for example, be processing the data
    # returned from a previous poll().
    time.sleep(sleep_length)

    # Poll the subscribed data from the data server. Poll will block and record
    # for poll_length seconds.
    poll_length = 0.1  # [s]
    poll_timeout = 500  # [ms]
    poll_flags = 0
    poll_return_flat_dict = True
    data = daq.poll(poll_length, poll_timeout, poll_flags, poll_return_flat_dict)

    # Unsubscribe from all paths.
    daq.unsubscribe("*")

    # Check the dictionary returned is non-empty
    assert (
        data
    ), "poll() returned an empty data dictionary, did you subscribe to any paths?"

    # The data returned is a dictionary of dictionaries that reflects the node's path.
    # Note, the data could be empty if no data had arrived, e.g., if the demods
    # were disabled or had demodulator rate 0.
    assert path in data, "The data dictionary returned by poll has no key `%s`." % path

    # Access the demodulator sample using the node's path.
    sample = data[path]

    # Let's check how many seconds of demodulator data were returned by poll.
    # First, get the sampling rate of the device's ADCs, the device clockbase...
    clockbase = float(daq.getInt("/%s/clockbase" % device))
    # ... and use it to convert sample timestamp ticks to seconds:
    dt_seconds = (sample["timestamp"][-1] - sample["timestamp"][0]) / clockbase
    print(f"poll() returned {dt_seconds:.3f} seconds of demodulator data.")
    tol_percent = 10
    dt_seconds_expected = sleep_length + poll_length
    assert (
        dt_seconds - dt_seconds_expected
    ) / dt_seconds_expected * 100 < tol_percent, (
        "Duration of demod data returned by poll() (%.3f s) differs " % dt_seconds
        + "from the expected duration (%.3f s) by more than %0.2f %%."
        % (dt_seconds_expected, tol_percent)
    )

    # Calculate the demodulator's magnitude and phase and add them to the dict.
    # The phase is returned in units of radian. We can use a keyword for the numpy
    # angle function to return degree units instead: np.angle( ... , deg=True)
    sample["R"] = np.abs(sample["x"] + 1j * sample["y"])
    sample["phi"] = np.angle(sample["x"] + 1j * sample["y"])
    print(f"Average measured RMS amplitude is {np.mean(sample['R']):.3e} V.")

    if plot:

        # Convert timestamps from ticks to seconds via clockbase.
        t = (sample["timestamp"] - sample["timestamp"][0]) / clockbase

        # Create plot
        _, axis = plt.subplots()
        axis.grid(True)
        axis.plot(t, sample["R"])
        axis.set_title("Demodulator data")
        axis.set_xlabel("Time (s)")
        axis.set_ylabel("R (V)")
        mean_r = np.mean(sample["R"])
        axis.axis([t[0], t[-1], 0.99 * mean_r, 1.01 * mean_r])

        plt.show()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
