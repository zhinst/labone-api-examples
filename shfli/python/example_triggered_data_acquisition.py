# Copyright 2023 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to acquired triggered demodulator data.

Requirements:
    * LabOne Version >= 24.01
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
from timeit import default_timer as timer
import importlib.util


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

    """ Configure the device """
    demod_index = 0

    # Use a software trigger for the sake of the example
    software_trigger = 1024
    daq.setInt(f"/{device}/demods/{demod_index}/trigger/source", software_trigger)

    # Enable the triggered acquisition
    daq.setInt(f"/{device}/demods/{demod_index}/trigger/triggeracq", 1)

    # Set the number of samples to be measured following a trigger event
    burst_length = 256
    daq.setInt(f"/{device}/demods/{demod_index}/burstlen", burst_length)

    # Adjust the data rate of demodulator 1
    data_rate = 2048  # [Sa/s]
    daq.setDouble(f"/{device}/demods/{demod_index}/rate", data_rate)

    # Enable the data transfer from demodulator 1 to data server
    daq.setInt(f"/{device}/demods/{demod_index}/enable", 1)

    # Time difference (s) between two consecutive timestamp ticks
    dt_device = daq.getDouble(f"/{device}/system/properties/timebase")

    """ Configure the DAQ Module """
    daq_module = daq.dataAcquisitionModule()
    # Set the device that will be used for the trigger - this parameter must be set.
    daq_module.set("device", device)
    # Configure the daq module to look out for bursts coming from the device (triggering is handled by the device)
    # The option can either be `burst_trigger` or 9
    daq_module.set("type", "burst_trigger")
    # No offset for the trigger position
    daq_module.set("delay", 0.0)
    # Set grid mode to be 'exact' or 4, meaning no interpolation from the daq module
    daq_module.set("grid/mode", "exact")
    # Set the grid columns to be equal to the burst length, given that the grid/mode is exact
    daq_module.set("grid/cols", burst_length)
    # Set the number of expected triggers to be acquired
    trigger_count = 3
    daq_module.set("count", trigger_count)
    # Set the DAQ module to trigger on a change of trigger index, i.e. on HW triggers.
    triggernode_path = f"/{device}/demods/{demod_index}/sample.trigindex"
    daq_module.set("triggernode", triggernode_path)

    # Subscribe to the signal path of demodulator 1 for acquisition
    trigger_signal_path = f"/{device}/demods/{demod_index}/sample.r"
    daq_module.subscribe(trigger_signal_path)
    daq_module.execute()

    # Issue multiple triggers according to trigger_count value
    for _ in range(trigger_count):
        # Issue the software trigger
        daq.setInt(f"/{device}/system/swtriggers/0/single", 1)

        # Let the device process the trigger before triggering again
        time.sleep(1)

        # Note: Certain triggers could be missed depending on circumstances such as the pause between issuing new triggers.
        # As a result the number of triggers retrieved might be less than the trigger_count

    start = timer()
    while daq_module.progress()[0] < 1.0 and not daq_module.finished():
        time.sleep(1)
        print(f"Progress {float(daq_module.progress()[0]) * 100:.2f} %\r")
        now = timer()
        if now - start > 60:  # timeout is 60 seconds
            print("The DAQ module did not finish in the required time!")
            return

    # Retrieve the data processed by the daq module
    data = daq_module.read(flat=True)

    # Clear the session
    daq_module.clear()

    # Disconnects from the data server
    daq.disconnect()

    # The data returned is a dictionary that reflects the node's path.
    # Note, the data could be empty if no data had arrived, e.g., if the demods
    # were disabled, had demod rate 0, in the absence of trigger or no subscription
    # were issued.
    assert (
        trigger_signal_path in data
    ), f"The data dictionary returned by poll has no key {trigger_signal_path}."

    # Access the demodulator sample using the node's path
    demod_data = data[trigger_signal_path]

    # Check that each burst has the expected size based on the grid columns
    for burst in demod_data:
        grid_cols = burst["header"]["gridcols"][0]
        if burst["value"].shape[1] != grid_cols:
            print("Warning: A burst is not complete")

    if plot:
        # check if plotly library is installed, otherwise use matplotlib
        plotly_check = importlib.util.find_spec("plotly")
        if plotly_check:
            plot_plotly(demod_data, dt_device)
        else:
            plot_matplotlib(demod_data, dt_device)


def filter_data(burst, dt_device):
    nonzero_indices = np.nonzero(burst["timestamp"])
    times = burst["timestamp"][nonzero_indices]
    times = (times - times[0]) * dt_device
    return times, burst["value"][nonzero_indices]


def plot_matplotlib(demod_data, dt_device):
    for idx, burst in enumerate(demod_data):
        times, values = filter_data(burst, dt_device)
        plt.plot(times, values, label="Burst " + str(idx + 1))
    plt.legend(loc="upper left")
    plt.xlabel("Time (s)")
    plt.ylabel("Signal (V)")
    plt.show()


def plot_plotly(demod_data, dt_device):
    try:
        import plotly.graph_objects as go
    except ImportError:
        print(
            "'plotly' module was not found! Check that the module is installed in your python environment!"
        )
        return
    fig = go.Figure()
    for idx, burst in enumerate(demod_data):
        times, values = filter_data(burst, dt_device)
        fig.add_trace(
            go.Scatter(
                x=times,
                y=values,
                name="Burst " + str(idx + 1),
                visible=True,
            )
        )
    fig.update_xaxes(title_text="Time (s)")
    fig.update_yaxes(title_text="Signal (V)")
    fig.show()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
