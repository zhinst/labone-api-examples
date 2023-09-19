# Copyright 2023 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to acquired triggered demodulator data.

Requirements:
    * LabOne Version >= 23.10
    * Instruments:
        1 x SHFLI

Usage:
    example_triggered_data_acquisition.py [options] <device_id>
    example_triggered_data_acquisition.py -h | --help

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

import time
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

    # Use a software trigger for the sake of the example
    software_trigger = 1024
    daq.setInt(f"/{device}/demods/0/trigger/source", software_trigger)

    # Enable the triggered acquisition
    daq.setInt(f"/{device}/demods/0/trigger/triggeracq", 1)

    # Set the number of samples to be measured following a trigger event
    burst_length = 256
    daq.setInt(f"/{device}/demods/0/burstlen", burst_length)

    # Adjust the data rate of demodulator 1
    data_rate = 2048  # [Sa/s]
    daq.setDouble(f"/{device}/demods/0/rate", data_rate)

    # Enable the data transfer from demodulator 1 to data server
    daq.setInt(f"/{device}/demods/0/enable", 1)

    # Time difference (s) between two consecutive timestamp ticks
    dt_device = daq.getDouble(f"/{device}/system/properties/timebase")

    # Subscribe to the signal path of demodulator 1 for acquisition
    path = f"/{device}/demods/0/sample"
    daq.subscribe(path)

    # Issue a first software trigger
    daq.setInt(f"/{device}/system/swtriggers/0/single", 1)

    # Let the device process the trigger before triggering again
    time.sleep(1)

    # Issue a second software trigger
    daq.setInt(f"/{device}/system/swtriggers/0/single", 1)

    # Poll the subscribed data from the data server. Poll will block and record
    # for poll_duration seconds.
    poll_duration = 1  # [s]
    poll_timeout = 500  # [ms]
    data = daq.poll(poll_duration, poll_timeout, flat=True)

    # Unsubscribe from all paths
    daq.unsubscribe("*")

    # Disconnect the device from data server
    daq.disconnectDevice(device)

    # The data returned is a dictionary that reflects the node's path.
    # Note, the data could be empty if no data had arrived, e.g., if the demods
    # were disabled, had demod rate 0, in the absence of trigger or no subscription
    # were issued.
    assert path in data, f"The data dictionary returned by poll has no key {path}."

    # Access the demodulator sample using the node's path
    demod_data = data[path]

    # Assemble the demodulator vectors into bursts (one burst corresponds to one trigger)
    bursts = assemble_bursts(demod_data)

    for burst in bursts:
        if not is_complete(burst):
            print(
                "Warning: A burst is not complete, is the data rate too high or the poll duration too short?"
            )

    if plot:
        plot_amp_phase(bursts, dt_device)


def assemble_bursts(vectors):
    """Assemble bursts from demodulator vector data returned by poll()

    Args:
      vectors (list): list of demodulator vectors as returned by poll()

    Returns:
       bursts (list): list of assembled demodulator bursts
    """

    bursts = []
    get_trigger_index = lambda vector: vector["properties"]["triggerindex"]
    current_trigger_index = None
    for vector in vectors:
        if get_trigger_index(vector) != current_trigger_index:
            bursts.append(vector)
            current_trigger_index = get_trigger_index(vector)
        else:
            vector_x = vector["vector"]["x"]
            vector_y = vector["vector"]["y"]
            current_burst_vector = bursts[-1]["vector"]
            current_burst_vector["x"] = np.append(current_burst_vector["x"], vector_x)
            current_burst_vector["y"] = np.append(current_burst_vector["y"], vector_y)
    return bursts


def is_complete(burst):
    """Check whether the burst is complete

    Args:
      bursts (list): a demodulator burst as returned by assemble_bursts()

    Returns:
        True if the burst is complete, False otherwise.
    """

    num_samples = len(burst["vector"]["x"])
    expected_num_samples = burst["properties"]["burstlength"]
    return num_samples == expected_num_samples


def plot_amp_phase(bursts, dt_device):
    """Plot demodulator bursts

    Args:
      bursts (list): list of demodulator bursts as returned by assemble_bursts()
    """

    _, (ax1, ax2) = plt.subplots(2, 1)

    for burst in bursts:
        x = burst["vector"]["x"]
        y = burst["vector"]["y"]
        props = burst["properties"]
        timestamps = props["timestamp"] + np.arange(len(x)) * props["dt"]

        initial_timestamp = bursts[0]["properties"]["timestamp"]
        time = dt_device * (timestamps - initial_timestamp)
        r = np.abs(x + 1j * y)
        phi = np.angle(x + 1j * y)

        ax1.plot(time, r)
        ax2.plot(time, phi)

    ax1.grid()
    ax1.set_ylabel(r"Demodulator R ($V_\mathrm{RMS}$)")

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
