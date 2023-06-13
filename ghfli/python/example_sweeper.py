# Copyright 2023 Zurich Instruments AG

"""
Demonstrate how to perform a frequency sweep using the Sweeper Module.

Requirements:
    * LabOne Version >= 23.06
    * Instruments:
        1 GHFLI Instrument

Usage:
    example_sweeper.py [options] <device_id>
    example_sweeper.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: GHFLI]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    --save                    Saves the data to file.
    --no-plot                 Hide plot of the recorded data.

Raises:
    Exception     If the specified devices do not match the requirements.
    Exception     If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import os
import time
import numpy as np
import zhinst.core
import zhinst.utils
import matplotlib.pyplot as plt


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
    save: bool = False,
):
    """run the example."""

    apilevel_example = 6
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host, server_port
    )

    # Index of the demodulator which data should be acquired.
    demod_index = 0
    # Rate of data transfer from the instrument to the host computer
    data_rate = 100e3  # [Sa/s]

    # Instrument settings:
    # Adjust the data rate of the demodulator
    daq.setDouble(f"/{device}/demods/{demod_index}/rate", data_rate)
    # Enable the data transfer from demodulator 1 to data server
    daq.setInt(f"/{device}/demods/{demod_index}/enable", 1)

    # Create an instance of the Sweeper Module (SweeperModule class).
    sweeper = daq.sweep()

    # Sweep parameters:
    start_frequency = 0.1e9  # [Hz]
    stop_frequency = 1.5e9  # [Hz]
    osc_index = 0
    # The minimum number of samples to accumulate per sweep point.
    num_samples = 100
    # Cap the bandwidth to avoid aliasing.
    max_bandwidth = 10e3  # NEP [Hz]

    # Configure the Sweeper Module's parameters.
    # Set the device that will be used for the sweep - this parameter must be set first.
    sweeper.set("device", device)
    # Specify the frequency of the oscillator `osc_index` should be swept.
    sweeper.set("gridnode", f"/{device}/oscs/{osc_index}/freq")
    # Set the `start` and `stop` values of the gridnode value interval we will use in the sweep.
    sweeper.set("start", start_frequency)
    sweeper.set("stop", stop_frequency)
    sweeper.set("samplecount", num_samples)
    # Specify that the sweep should go from start to stop.
    sweeper.set("scan", "sequential")
    # Specify that a linear spacing should be used for the grid points.
    sweeper.set("xmapping", "linear")
    sweeper.set("maxbandwidth", max_bandwidth)

    # Now subscribe to the nodes from which data will be recorded.
    path = f"/{device}/demods/{demod_index}/sample"
    sweeper.subscribe(path)

    # Start the sweeper running.
    sweeper.execute()

    start = time.time()
    timeout = 60  # [s]
    while not sweeper.finished():  # Wait until the sweep is complete, with timeout.
        time.sleep(0.2)
        progress = sweeper.progress()
        print(f"Sweep progress: {progress[0]:.2%}.", end="\r")
        # Here we could read intermediate data via:
        # data = sweeper.read(True)...
        # and process it while the sweep is completing.
        # if device in data:
        # ...
        if (time.time() - start) > timeout:
            # If for some reason the sweep is blocking, force the end of the
            # measurement.
            print("\nSweep still not finished, forcing finish...")
            sweeper.finish()
    print("")

    if save:
        save_data_to_file(sweeper)

    # Read the sweep data. This command can also be executed whilst sweeping
    # (before finished() is True), in this case sweep data up to that time point
    # is returned. It's still necessary to issue read() at the end to
    # fetch the rest.
    data = sweeper.read(flat=True)

    sweeper.unsubscribe(path)

    # Note: data could be empty if no data arrived, e.g., if the demods were
    # disabled or had rate 0.
    assert path in data, f"No sweep data in data dictionary: it has no key {path}"
    samples = data[path]

    if plot:
        row_index = 0
        col_index = 0
        plot_measured_data(samples[row_index][col_index])


def save_data_to_file(sweeper: zhinst.core.SweeperModule):
    # Set the filename stem for saving the data to file. The data are saved in a separate
    # numerically incrementing sub-directory prefixed with the /save/filename value each
    # time a save command is issued.
    script_dir = os.path.dirname(os.path.realpath(__file__))
    sweeper.set("save/directory", script_dir)
    sweeper.set("save/filename", "sweep_with_save")
    # Set the file format to use: "mat", "csv", "zview" or "hdf5".
    sweeper.set("save/fileformat", "hdf5")

    # Indicate that the data should be saved to file. This must be done before the read()
    # command. Otherwise there is no longer any data to save.
    sweeper.set("save/save", 1)
    # Wait until the save is complete. The saving is done asynchronously in the background
    # so we need to wait until it is complete. In the case of the sweeper it is important
    # to wait for completion before before performing the module read command. The sweeper has
    # a special fast read command which could otherwise be executed before the saving has
    # started.
    while sweeper.getInt("save/save") != 0:
        time.sleep(0.1)


def plot_measured_data(sweep_data: dict):
    _, (ax1, ax2) = plt.subplots(2, 1)

    frequency = sweep_data["grid"]
    demod_r = np.abs(sweep_data["x"] + 1j * sweep_data["y"])
    phi = np.angle(sweep_data["x"] + 1j * sweep_data["y"])
    ax1.plot(frequency, demod_r)
    ax2.plot(frequency, phi)
    ax1.grid()
    ax1.set_ylabel(r"Demodulator R ($V_\mathrm{RMS}$)")

    ax2.grid()
    ax2.set_xlabel("Frequency ($Hz$)")
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
