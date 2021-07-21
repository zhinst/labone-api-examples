# Copyright 2018 Zurich Instruments AG

"""
Run a basic test of the result unit.

This example demonstrates how to use the result unit for acquiring data
after weighted integration, rotation, and crosstalk suppression.

A single non-zero coefficient in each weighting function is activated. As a
consequence, the result unit will sample just a single input sample each
time it is started. We then configure the AWG to output a bipolar square
wave. The AWG plays the waveform in a loop for each measurement and all
averages. The AWG sweeps the starting point of the integration for each
measurement. The final result is that we record essentially the input
waveform using the result unit. The step size corresponds to the wait time
in the AWG, which is 4.44 ns. Finally, we configure a different coefficient
for each of the 10 input channels to enable the user to differentiate the
channels in the plot output.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x UHFQA Instrumemt.
    * Signal output 1 connected to signal input 1 with a BNC cable.
    * Signal output 2 connected to signal input 2 with a BNC cable.

Usage:
    example_result.py [options] <device_id>
    example_result.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: UHFQA]

Options:
    -h --help                   Show this screen.
    --no-plot                   Hide plot of the recorded data.
    -l --result_length LENGTH   Number of measurements. [default: 2600]
    -a --num_averages VAL       Number of averages per measurement. [default: 1]

Returns:
    data  Measurement result. (dict)

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import textwrap
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt
import common_uhfqa


def run_example(
    device_id: str, result_length: int = 2600, num_averages: int = 1, plot: bool = True
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

    # Configure AWG
    awg_program = textwrap.dedent(
        """\
    const RATE = 0;
    const FS = 1.8e9*pow(2, -RATE);
    const LENGTH = 1.0e-6;
    const N = floor(LENGTH*FS);

    wave w = join(zeros(64), ones(10000), -ones(10000));

    setTrigger(AWG_INTEGRATION_ARM);
    var loop_cnt = getUserReg(0);
    var avg_cnt = getUserReg(1);
    var wait_delta = 1;

    repeat (avg_cnt) {
        var wait_time = 0;

        repeat(loop_cnt) {
            wait_time += wait_delta;
            playWave(w, w);
            wait(wait_time);
            setTrigger(AWG_INTEGRATION_TRIGGER + AWG_INTEGRATION_ARM);
            setTrigger(AWG_INTEGRATION_ARM);
            waitWave();
            wait(1024);
        }
    }

    setTrigger(0);
    """
    )

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

    # Apply a rotation on half the channels to get the imaginary part instead
    for i in range(5):
        daq.setComplex(f"/{device:s}/qas/0/rotations/{i:d}", 1)
        daq.setComplex(f"/{device:s}/qas/0/rotations/{i + 5:d}", -1j)

    # Channels to test
    channels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

    # Configuration of weighted integration
    #
    # A single non-zero coefficient in each weighting function is activated.
    # As a consequence, the result unit will sample just a single input
    # sample each time it is started.
    weights = np.linspace(1.0, 0.1, 10)
    for i in channels:
        weight = np.array([weights[i]])
        daq.setVector(f"/{device:s}/qas/0/integration/weights/{i}/real", weight)
        daq.setVector(f"/{device:s}/qas/0/integration/weights/{i}/imag", weight)

    daq.setInt(f"/{device:s}/qas/0/integration/length", 1)
    daq.setInt(f"/{device:s}/qas/0/integration/mode", 0)
    daq.setInt(f"/{device:s}/qas/0/delay", 0)

    # Provide result length and number of averages in user register
    daq.setDouble(f"/{device:s}/awgs/0/userregs/0", result_length)
    daq.setDouble(f"/{device:s}/awgs/0/userregs/1", num_averages)

    # Configure the result unit
    daq.setInt(f"/{device:s}/qas/0/result/length", result_length)
    daq.setInt(f"/{device:s}/qas/0/result/averages", num_averages)
    daq.setInt(
        f"/{device:s}/qas/0/result/source", common_uhfqa.ResultLoggingSource.TRANS
    )

    # Now we're ready for readout. Enable result unit and start acquisition.
    daq.setInt(f"/{device:s}/qas/0/result/reset", 1)
    daq.setInt(f"/{device:s}/qas/0/result/enable", 1)
    daq.sync()

    # Subscribe to result waves
    paths = []
    for channel in channels:
        path = f"/{device:s}/qas/0/result/data/{channel:d}/wave"
        paths.append(path)
    daq.subscribe(paths)

    # Arm the device
    daq.asyncSetInt(f"/{device:s}/awgs/0/single", 1)
    daq.syncSetInt(f"/{device:s}/awgs/0/enable", 1)

    # Perform acquisition
    print("Acquiring data...")
    data = common_uhfqa.acquisition_poll(daq, paths, result_length)
    print("Done.")

    # Stop result unit
    daq.unsubscribe(paths)
    daq.setInt(f"/{device:s}/qas/0/result/enable", 0)

    if plot:
        fig, axes = plt.subplots(figsize=(12, 4))
        axes.set_title("Result unit")
        axes.set_ylabel("Amplitude (a.u.)")
        axes.set_xlabel("Measurement (#)")
        for path, samples in data.items():
            axes.plot(samples, label=f"{path}")
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
