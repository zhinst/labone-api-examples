# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Run a basic test of the input averager.

    The example plays gaussian waveforms on each output using the AWG and runs
    the monitor to record them.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x UHFQA Instrumemt.
    * Signal output 1 connected to signal input 1 with a BNC cable.
    * Signal output 2 connected to signal input 2 with a BNC cable.

Usage:
    example_monitor.py [options] <device_id>
    example_monitor.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: UHFQA]

Options:
    -h --help                   Show this screen.
    -p --plot                   create a plot.
    -v --vector_length LENGTH   Length of the output waveform. [default: 4000]
    -l --monitor_length LENGTH  Number of monitor samples to obtain. [default: 4000]
    -a --num_averages VAL       Number of averages per measurement.  [default: 256]

Returns:
    data  Measurement result. (dict)

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
import textwrap
import zhinst.utils
import matplotlib.pyplot as plt

import common_uhfqa


def run_example(
    device_id: str,
    vector_length: int = 4000,
    monitor_length: int = 4000,
    num_averages: int = 256,
    plot: bool = True,
):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    required_devtype = "UHFQA"
    required_options = None
    daq, device, _ = zhinst.utils.create_api_session(
        device_id,
        apilevel_example,
        required_devtype=required_devtype,
        required_options=required_options,
    )

    # Perform initialization for UHFQA examples
    common_uhfqa.initialize_device(daq, device)

    # Configure AWG to output gaussian pulses on output 1 and 2
    awg_program = textwrap.dedent(
        """\
    const LENGTH = ${LENGTH};
    wave w = gauss(LENGTH, LENGTH/2, LENGTH/8);

    var loop_cnt = getUserReg(0);
    var wait_time = 0;

    repeat(loop_cnt) {
      setTrigger(0);
      playWave(w, -w);
      wait(50);
      setTrigger(AWG_MONITOR_TRIGGER);
      setTrigger(0);
      waitWave();
      wait(1000);
    }
    """
    ).replace("${LENGTH}", f"{vector_length:d}")

    # Provide number of averages in user register
    daq.setDouble(f"/{device:s}/awgs/0/userregs/0", num_averages)

    # Create an instance of the AWG module
    awgModule = daq.awgModule()
    awgModule.set("device", device)
    awgModule.set("index", 0)
    awgModule.execute()

    # Transfer the AWG sequence program. Compilation starts automatically.
    awgModule.set("compiler/sourcestring", awg_program)
    while awgModule.getInt("compiler/status") == -1:
        time.sleep(0.1)

    # Ensure that compilation was successful
    assert awgModule.getInt("compiler/status") != 1

    # Enable outputs
    daq.setInt(f"/{device:s}/sigouts/*/on", 1)

    # Setup monitor
    daq.setInt(f"/{device:s}/qas/0/monitor/averages", num_averages)
    daq.setInt(f"/{device:s}/qas/0/monitor/length", monitor_length)
    monitor_length = daq.getInt(f"/{device:s}/qas/0/monitor/length")

    # Now we're ready for readout. Enable monitor and start acquisition.
    daq.setInt(f"/{device:s}/qas/0/monitor/reset", 1)
    daq.setInt(f"/{device:s}/qas/0/monitor/enable", 1)
    daq.sync()

    # Subscribe to monitor waves
    paths = []
    for channel in range(2):
        path = f"/{device:s}/qas/0/monitor/inputs/{channel:d}/wave"
        paths.append(path)
    daq.subscribe(paths)

    # Arm the device
    daq.asyncSetInt(f"/{device:s}/awgs/0/single", 1)
    daq.syncSetInt(f"/{device:s}/awgs/0/enable", 1)

    # Perform acquisition
    print("Acquiring data...")
    data = common_uhfqa.acquisition_poll(daq, paths, monitor_length)
    print("Done.")

    # Stop monitor
    daq.unsubscribe(paths)
    daq.setInt(f"/{device:s}/qas/0/monitor/enable", 0)

    if plot:
        fig, axes = plt.subplots(figsize=(12, 4))
        axes.set_title(f"Input averager results after {num_averages:d} measurements")
        axes.set_ylabel("Amplitude (a.u.)")
        axes.set_xlabel("Sample (#)")
        for path, samples in data.items():
            axes.plot(samples, label=f"Readout {path}")
        plt.legend(loc="best")
        fig.set_tight_layout(True)
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
