# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to obtain impedance data using ziDAQServer's blocking
(synchronous) poll() command.
Connect to the device specified by device_id and obtain
impedance data using ziDAQServer's blocking (synchronous) poll() command.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with IA option
    * Connect Impedance Testfixture and attach a 1kOhm resistor

Usage:
    example_autoranging_impedance.py [options] <device_id>
    example_autoranging_impedance.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: MF*(IA)]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]
    --no-plot              Hide plot of the recorded data.

Returns:
    sample  The impedance sample dictionary as returned by poll.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""
import time
import zhinst.utils
import matplotlib.pyplot as plt
import numpy as np

import example_autoranging_impedance


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # We use the auto-range example to perform some basic device configuration
    # and wait until signal input ranges have been configured by the device.
    example_autoranging_impedance.run_example(device)

    # Subscribe to the impedance sample node path.
    imp_index = 0
    path = "/%s/imps/%d/sample" % (device, imp_index)
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
    # Note, the data could be empty if no data had arrived, e.g., if the imps
    # were disabled or had transfer rate 0.
    assert path in data, "The data dictionary returned by poll has no key `%s`." % path

    # Access the impedance sample using the node's path. For more information
    # see the data structure documentation for ZIImpedanceSample in the LabOne
    # Programming Manual.
    impedance_sample = data[path]

    # Get the sampling rate of the device's ADCs, the device clockbase in order
    # to convert the sample's timestamps to seconds.
    clockbase = float(daq.getInt("/%s/clockbase" % device))

    dt_seconds = (
        impedance_sample["timestamp"][-1] - impedance_sample["timestamp"][0]
    ) / clockbase
    num_samples = len(impedance_sample["timestamp"])
    print(
        f"poll() returned {num_samples} samples of impedance data spanning {dt_seconds:.3f} \
            seconds."
    )
    print(f"Average measured resitance: {np.mean(impedance_sample['param0'])} Ohm.")
    print(f"Average measured capacitance: {np.mean(impedance_sample['param1'])} F.")

    if plot:

        # Convert timestamps from ticks to seconds via clockbase.
        t = (
            impedance_sample["timestamp"] - impedance_sample["timestamp"][0]
        ) / clockbase

        plt.close("all")
        # Create plot
        _, axes = plt.subplots(2, sharex=True)
        axes[0].plot(t, impedance_sample["param0"])
        axes[0].set_title("Impedance Parameters")
        axes[0].grid(True)
        axes[0].set_ylabel(r"Resistance ($\Omega$)")
        axes[0].autoscale(enable=True, axis="x", tight=True)

        axes[1].plot(t, impedance_sample["param1"])
        axes[1].grid(True)
        axes[1].set_ylabel(r"Capacitance (F)")
        axes[1].set_xlabel("Time (s)")
        axes[1].autoscale(enable=True, axis="x", tight=True)

        plt.draw()
        plt.show()

    return data


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
