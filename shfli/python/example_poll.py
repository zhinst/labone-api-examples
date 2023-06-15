# Copyright 2023 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to obtain demodulator data using ziDAQServer's blocking
(synchronous) poll() command.

Requirements:
    * LabOne Version >= 23.02
    * Instruments:
        1 x SHFLI

Usage:
    example_poll.py [options] <device_id>
    example_poll.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: SHFLI]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    --no-plot                 Hide plot of the recorded data.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
):
    """run the example."""

    apilevel_example = 6
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )

    # Adjust the data rate of demodulator 1
    data_rate = 2000  # [Sa/s]
    daq.setDouble(f"/{device}/demods/0/rate", data_rate)

    # Enable the data transfer from demodulator 1 to data server
    daq.setInt(f"/{device}/demods/0/enable", 1)

    # Enable the continuous acquisition of demodulator 1 data
    daq.setInt(f"/{device}/demods/0/trigger/triggeracq", 0)

    # Time difference (s) between two consecutive timestamp ticks
    dt_device = daq.getDouble(f"/{device}/system/properties/timebase")

    # Current timestamp of the instrument
    start_timestamp = daq.getInt(f"/{device}/status/time")

    # Subscribe to the signal path of demodulator 1 for acquisition
    path = f"/{device}/demods/0/sample"
    daq.subscribe(path)

    # Poll the subscribed data from the data server. Poll will block and record
    # for poll_duration seconds.
    poll_duration = 6  # [s]
    poll_timeout = 500  # [ms]
    data = daq.poll(poll_duration, poll_timeout, flat=True)

    # Unsubscribe from all paths.
    daq.unsubscribe("*")

    # Disconnect the device from data server
    daq.disconnectDevice(device)

    # The data returned is a dictionary that reflects the node's path.
    # Note, the data could be empty if no data had arrived, e.g., if the demods
    # were disabled, configured in triggered mode, had demod rate 0 or no
    # subscription were issued.
    assert path in data, f"The data dictionary returned by poll has no key {path}."

    # Access the demodulator sample using the node's path.
    demod_data = data[path]

    if not are_contiguous(demod_data):
        print("Warning: The data chunks are not contiguous, is the data rate too high?")

    if plot:
        plot_amp_phase(demod_data, start_timestamp, dt_device)


def are_contiguous(vectors):
    """Check whether the vectors are contiguous

    Args:
      vectors (list): list of demodulator vectors as returned by poll()

    Returns:
        True if the vectors are contiguous, False otherwise.
    """
    expected_next_timestamp = None
    for vector in vectors:
        vector_props = vector["properties"]
        if (
            expected_next_timestamp is not None
            and vector_props["timestamp"] != expected_next_timestamp
        ):
            return False
        vector_len = len(vector["vector"]["x"])
        expected_next_timestamp = (
            vector_props["timestamp"] + vector_len * vector_props["dt"]
        )
    return True


def concatenate(vectors):
    """Concatenate demodulator vectors

    Args:
      vectors (list): list of demodulator vectors as returned by poll()

    Returns:
        x, y, timestamp (np.array, np.array, np.array): the concatenated measurements
    """

    x = np.array([])
    y = np.array([])
    timestamp = np.array([])
    for vector in vectors:
        vector_x = vector["vector"]["x"]
        vector_y = vector["vector"]["y"]
        vector_props = vector["properties"]
        vector_timestamp = (
            vector_props["timestamp"] + np.arange(len(vector_x)) * vector_props["dt"]
        )
        x = np.append(x, vector_x)
        y = np.append(y, vector_y)
        timestamp = np.append(timestamp, vector_timestamp)
    return x, y, timestamp


def plot_amp_phase(vectors, start_timestamp, dt_device):
    x, y, timestamp = concatenate(vectors)
    start_mask = timestamp >= start_timestamp
    x = x[start_mask]
    y = y[start_mask]
    timestamp = timestamp[start_mask]

    time = dt_device * (timestamp - start_timestamp)
    r = np.abs(x + 1j * y)
    phi = np.angle(x + 1j * y)

    _, (ax1, ax2) = plt.subplots(2, 1)
    ax1.plot(time, r)
    ax1.grid()
    ax1.set_ylabel(r"Demodulator R ($V_\mathrm{RMS}$)")

    ax2.plot(time, phi)
    ax2.grid()
    ax2.set_xlabel("Time ($s$)")
    ax2.set_ylabel(r"Demodulator Phi (radians)")

    plt.show()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
