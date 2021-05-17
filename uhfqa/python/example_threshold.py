# Copyright 2018 Zurich Instruments AG

"""
Run a test of the result unit together with thresholding and statistics.

The example applies a simple square wave to the instrument using the AWG.
The integration functions use the full length of the integrators, and each
integration function is basically just a constant value through the entire
integration window, with different values for the different channels. We
then sweep the starting point of the integration in relation to the pulse
generated by the AWG. Initially, the integrators will not see the pulse at
all, so the result will be zero. Then, as we gradually get more and more
overlap of the integration function and the pulse, we will see a ramp up
until a point in time where the integration window is completely within the
pulse. Then, for larger delays we have the reverse process. We configure a
fixed threshold for all channels and then we show how the threshold output
toggles as the integration result goes above the threshold. We also read out
the results from the statistics unit and show that in a table.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x UHFQA Instrumemt.
    * Signal output 1 connected to signal input 1 with a BNC cable.
    * Signal output 2 connected to signal input 2 with a BNC cable.

Usage:
    example_threshold.py [options] <device_id>
    example_threshold.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: UHFQA]

Options:
    -h --help                   Show this screen.
    -p --plot                   create a plot.
    -t --threshold VAL          Quantization threshold. [default: 500]
    -l --result_length LENGTH   Number of measurements. [default: 2600]
    -a --num_averages VAL       Number of averages per measurement. [default: 1]

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
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt
import common_uhfqa


def run_example(
    device_id: str,
    threshold: int = 500,
    result_length: int = 1500,
    num_averages: int = 1,
    plot: bool = False,
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
    const F_RES = 1.6e6;
    const LENGTH = 3.0e-6;
    const N = floor(LENGTH*FS);

    wave w = join(zeros(N), ones(N), zeros(N));

    setTrigger(AWG_INTEGRATION_ARM);
    var loop_cnt = getUserReg(0);
    var avg_cnt = getUserReg(1);
    var wait_delta = getUserReg(2);

    repeat (avg_cnt) {
        var wait_time = 0;

        repeat(loop_cnt) {
            wait_time = wait_time + wait_delta;
            setTrigger(AWG_INTEGRATION_ARM);
            playWave(w, w, RATE);
            wait(wait_time);
            setTrigger(AWG_INTEGRATION_TRIGGER + AWG_INTEGRATION_ARM);
            setTrigger(AWG_INTEGRATION_ARM);
            waitWave();
            wait(1000);
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

    # Configure AWG program from registers
    daq.setDouble(f"/{device:s}/awgs/0/userregs/0", result_length)
    daq.setDouble(f"/{device:s}/awgs/0/userregs/1", num_averages)
    daq.setDouble(f"/{device:s}/awgs/0/userregs/2", 1)

    # Configuration of weighted integration
    channels = [0, 1, 2, 3, 4, 5, 6, 7]
    weights = np.linspace(1, 0.1, 10)
    integration_length = 4096
    for i, channel in enumerate(channels):
        weight = weights[i] * np.ones(integration_length)
        daq.setVector(f"/{device:s}/qas/0/integration/weights/{channel}/real", weight)
        daq.setVector(f"/{device:s}/qas/0/integration/weights/{channel}/imag", weight)

    daq.setInt(f"/{device:s}/qas/0/integration/length", integration_length)
    daq.setInt(f"/{device:s}/qas/0/integration/mode", 0)
    daq.setInt(f"/{device:s}/qas/0/delay", 0)

    # Enable statistics
    daq.setInt(f"/{device:s}/qas/0/result/statistics/length", result_length)
    daq.setInt(f"/{device:s}/qas/0/result/statistics/reset", 1)
    daq.setInt(f"/{device:s}/qas/0/result/statistics/enable", 1)

    # Configure thresholds
    for channel in channels:
        daq.setDouble(f"/{device:s}/qas/0/thresholds/{channel:d}/level", threshold)

    # Configure the result unit
    daq.setInt(f"/{device:s}/qas/0/result/length", result_length)
    daq.setInt(f"/{device:s}/qas/0/result/averages", num_averages)

    # Subscribe to result waves
    paths = []
    for channel in channels:
        path = f"/{device:s}/qas/0/result/data/{channel:d}/wave"
        paths.append(path)
    daq.subscribe(paths)

    result_data = {}
    statistics = []
    for result_source in (
        common_uhfqa.ResultLoggingSource.TRANS,
        common_uhfqa.ResultLoggingSource.THRES,
    ):
        daq.setInt(f"/{device:s}/qas/0/result/source", result_source)

        # Now we're ready for readout. Enable result unit and start acquisition.
        daq.setInt(f"/{device:s}/qas/0/result/reset", 1)
        daq.setInt(f"/{device:s}/qas/0/result/enable", 1)
        daq.sync()

        # Arm the device
        daq.asyncSetInt(f"/{device:s}/awgs/0/single", 1)
        daq.syncSetInt(f"/{device:s}/awgs/0/enable", 1)

        # Perform acquisition
        print(f"Acquiring data for {result_source!r}...")
        result_data[result_source] = common_uhfqa.acquisition_poll(
            daq, paths, result_length
        )
        print("Done.")

        # Stop result unit
        daq.setInt(f"/{device:s}/qas/0/result/enable", 0)

        # Obtain statistics
        if result_source == common_uhfqa.ResultLoggingSource.TRANS:
            for channel in channels:
                num_ones = daq.getInt(
                    f"/{device:s}/qas/0/result/statistics/data/{channel:d}/ones"
                )
                num_flips = daq.getInt(
                    f"/{device:s}/qas/0/result/statistics/data/{channel:d}/flips"
                )
                statistics.append({"ones": num_ones, "flips": num_flips})

    # Unsubscribe
    daq.unsubscribe(paths)

    print("Statistics:")
    print(f"{'Readout channel':15s}  {'# ones':>10s} {'# flips':>10s}")
    for i, channel in enumerate(channels):
        print(
            f"{channel:15d}  {statistics[i]['ones']:10d} {statistics[i]['flips']:10d}"
        )

    if plot:
        fig, axes = plt.subplots(ncols=2, figsize=(12, 4), sharex=True)
        axes[0].set_title("Transformation unit")
        axes[0].set_ylabel("Amplitude (a.u.)")
        axes[0].set_xlabel("Measurement (#)")
        axes[0].axhline(threshold, color="k", linestyle="--")
        for path, samples in result_data[
            common_uhfqa.ResultLoggingSource.TRANS
        ].items():
            axes[0].plot(samples, label=f"{path}")
        axes[1].set_title("Thresholding unit")
        axes[1].set_ylabel("Amplitude (a.u.)")
        axes[1].set_xlabel("Measurement (#)")
        for path, samples in result_data[
            common_uhfqa.ResultLoggingSource.THRES
        ].items():
            axes[1].plot(samples, label=f"{path}")
        fig.set_tight_layout(True)
        plt.show()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
