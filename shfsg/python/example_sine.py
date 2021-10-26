# Copyright 2021 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Generate a sine wave with the SHFSG Instrument.

Requirements:
    * LabOne Version >= 21.08
    * Instruments:
        1 x SHFSG Instrument

Usage:
    example_sine.py [options] <device_id>
    example_sine.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: SHFSG]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    -i --interface INTERFACE  Interface between the data server and the Instrument [default: 1GbE]
    -c --channel ID           Signal Channel. (indexed from 0) [default: 0]
    -r --rf_frequency FREQ    Center Frequency of the synthesizer in GHz. [default: 1]
    -o --osc_frequency FREQ   Frequency of digital sine generator in MHz. [default: 100]
    -w --output_power POWER   Output power in dBm, in steps of 5dBm. [default: 0]
    -g --gain VALUE           Gain for sine generation. [default: 0.25]

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
      Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
      sub-folder.
"""

import zhinst.ziPython
import zhinst.utils


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    interface: str = "1GbE",
    channel: int = 0,
    rf_frequency: float = 1,
    osc_frequency: float = 100,
    output_power: float = 0,
    gain: float = 0.7,
):
    """run the example."""

    # connect device
    daq = zhinst.ziPython.ziDAQServer(host=server_host, port=server_port, api_level=6)
    daq.connectDevice(device_id, interface)
    zhinst.utils.api_server_version_check(daq)

    ## Set analog RF center frequencies, enable outputs, turn off modulation
    # Set RF center frequency
    synth_nmbr = daq.getInt(f"/{device_id}/SGCHANNELS/{channel}/SYNTHESIZER")
    daq.setDouble(
        f"/{device_id}/SYNTHESIZERS/{synth_nmbr}/CENTERFREQ", rf_frequency * 1e9
    )
    # Turn on output
    daq.setInt(f"/{device_id}/SGCHANNELS/{channel}/OUTPUT/ON", 1)
    # Set power in dBm, in steps of 5dBm
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/OUTPUT/RANGE", output_power)
    # Set SHFSG to use RF path (in case LF path was enabled earlier)
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/OUTPUT/RFLFPATH", 1)

    ## Configure digital sine generator
    # Set frequency of digital sine generator
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/OSCS/0/FREQ", osc_frequency * 1e6)
    # Turn on I port of sine generator
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/SINES/0/I/ENABLE", 1)
    # Turn on Q port of sine generator
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/SINES/0/Q/ENABLE", 1)

    ## Configure upper sideband modulation
    # Four gain settings needed for full complex modulation.
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/SINES/0/I/COS/AMPLITUDE", gain)
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/SINES/0/I/SIN/AMPLITUDE", -gain)
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/SINES/0/Q/COS/AMPLITUDE", gain)
    daq.setDouble(f"/{device_id}/SGCHANNELS/{channel}/SINES/0/Q/SIN/AMPLITUDE", gain)

    print(
        f"Sine wave with modulation frequency {osc_frequency} MHz "
        f"and center frequency {rf_frequency} GHz "
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
