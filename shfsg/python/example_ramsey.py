# Copyright 2021 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Generate a Ramsey sequence with the SHFSG Instrument.

Requirements:
    * LabOne Version >= 22.02
    * Instruments:
        1 x SHFSG or SHFQC Instrument

Usage:
    example_ramsey.py [options] <device_id>
    example_ramsey.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: SHFSG | SHFQC]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    -i --interface INTERFACE  Interface between the data server and the Instrument [default: 1GbE]
    -c --channel ID           Signal Channel. (indexed from 0) [default: 0]
    -r --rf_frequency FREQ    Center Frequency of the synthesizer in GHz. [default: 1]
    -l --rflf_path VALUE      Use RF (value 1) or LF (value 0) path. [default: 1]
    -n --osc_index ID         Digital oscillator to use [default: 0]
    -o --osc_frequency FREQ   Frequency of digital sine generator in MHz. [default: 100]
    -a --phase VALUE          Phase of sine generator. [default: 0]
    -w --output_power POWER   Output power in dBm, in steps of 5dBm. [default: 0]
    -b --global_amp VALUE     Dimensionless amplitude for scaling AWG outputs. [default: 0.5]
    -g --gains TUPLE          Gains for sine generation. [default: (1.0, -1.0, 1.0, 1.0)]

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
      Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
      sub-folder.
"""

import os
import zhinst.core
import zhinst.utils
import zhinst.utils.shfsg as shfsg_utils


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    interface: str = "1GbE",
    channel: int = 0,
    rf_frequency: float = 1,
    rflf_path: int = 1,
    osc_index: int = 0,
    osc_frequency: float = 100,
    phase: float = 0.0,
    output_power: float = 0,
    global_amp: float = 0.5,
    gains: tuple = (1.0, -1.0, 1.0, 1.0),
):
    """run the example."""

    # connect device
    daq = zhinst.core.ziDAQServer(host=server_host, port=server_port, api_level=6)
    daq.connectDevice(device_id, interface)
    zhinst.utils.api_server_version_check(daq)

    # Set analog RF center frequencies, output power, RF or LF path, enable outputs
    shfsg_utils.configure_channel(
        daq,
        device_id,
        channel,
        enable=1,
        output_range=output_power,
        center_frequency=rf_frequency * 1e9,
        rflf_path=rflf_path,
    )

    # Configure digital modulation of AWG signals
    shfsg_utils.configure_pulse_modulation(
        daq,
        device_id,
        channel,
        enable=1,
        osc_index=osc_index,
        osc_frequency=osc_frequency * 1e6,
        phase=phase,
        global_amp=global_amp,
        gains=gains,
    )

    # Set marker source
    daq.setInt(f"/{device_id}/SGCHANNELS/{channel}/MARKER/SOURCE", 0)

    # Upload sequencer programm to AWG Module
    with open(os.path.join(os.path.dirname(__file__), "Ramsey.seq")) as f:
        awg_seqc = f.read()
    shfsg_utils.load_sequencer_program(daq, device_id, channel, awg_seqc)

    # Upload command table to instrument
    with open(
        os.path.join(os.path.dirname(__file__), "Ramsey_command_table.json")
    ) as f:
        ct_str = f.read()
    daq.setVector(f"/{device_id}/SGCHANNELS/{channel}/AWG/COMMANDTABLE/DATA", ct_str)

    # Enable sequencer with single mode
    single = 1
    shfsg_utils.enable_sequencer(daq, device_id, channel, single=single)

    print(
        f"Ramsey sequence with modulation frequency {osc_frequency} MHz, "
        f"center frequency {rf_frequency} GHz "
        f"generated on channel {channel}."
    )


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
