# Copyright 2021 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Run a frequency sweep with a SHFQA

Requirements:
    * LabOne Version >= 21.08
    * Instruments:
        1 x SHFQA Instrument
    * Signal output 0 connected to signal input 0 with a BNC cable.

Usage:
    example_resonator.py [options] <device_id>
    example_resonator.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: SHFQA]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]
    --no-plot              Hide plot of the recorded data.

Returns:
    dict       Measurement result.

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
      Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
      sub-folder.
"""

import zhinst.utils
from zhinst.utils.shf_sweeper import (
    ShfSweeper,
    AvgConfig,
    RfConfig,
    SweepConfig,
)


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
):
    """run the example."""

    # connect device
    apilevel_example = 6
    (daq, dev, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )

    # instantiate ShfSweeper
    sweeper = ShfSweeper(daq, dev)

    # configure sweeper
    sweep_config = SweepConfig(
        start_freq=-200e6,
        stop_freq=300e6,
        num_points=51,
        mapping="linear",
        oscillator_gain=0.8,
    )
    avg_config = AvgConfig(integration_time=100e-6, num_averages=2, mode="sequential")
    rf_config = RfConfig(channel=0, input_range=0, output_range=0, center_freq=4e9)
    sweeper.configure(sweep_config, avg_config, rf_config)

    # set to device, can also be ignored
    sweeper.set_to_device()

    # turn on the input / output channel
    daq.setInt(f"/{dev}/qachannels/{rf_config.channel}/input/on", 1)
    daq.setInt(f"/{dev}/qachannels/{rf_config.channel}/output/on", 1)
    daq.sync()

    # start a sweep
    result = sweeper.run()
    print("Keys in the ShfSweeper result dictionary: ")
    print(result.keys())

    # alternatively, get result after sweep
    result = sweeper.get_result()
    num_points_result = len(result["vector"])
    print(f"Measured at {num_points_result} frequency points.")

    # simple plot over frequency
    if plot:
        sweeper.plot()

    return result


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
