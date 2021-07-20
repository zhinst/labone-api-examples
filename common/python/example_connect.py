# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments device via the Data Server
program.
Create an API session by connecting to a Zurich Instruments
device via the Data Server, ensure the demodulators are enabled and obtain a
single demodulator sample via getSample(). Calculate the sample's RMS
amplitude and add it as a field to the "sample" dictionary.

Note:
  This is intended to be a simple example demonstrating how to connect to a
  Zurich Instruments device from ziPython. In most cases, data acquisition
  should use either ziDAQServer's poll() method or an instance of the
  ziDAQRecorder class, not the getSample() method.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * Signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_connect.py <device_id>
    example_connect.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""
import numpy as np
import zhinst.utils


def run_example(
    device_id: str, server_host: str = "localhost", server_port: int = 8004
):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Enable the demodulator.
    daq.setInt("/%s/demods/0/enable" % device, 1)
    # Set the demodulator output rate.
    daq.setDouble("/%s/demods/0/rate" % device, 1.0e3)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that the settings have taken effect on the device before issuing
    # the getSample() command.
    daq.sync()

    # Obtain one demodulator sample. If the demodulator is not enabled (as
    # above) then the command will time out: we'll get a RuntimeError showing
    # that a `ZIAPITimeoutException` occured.
    sample = daq.getSample("/%s/demods/0/sample" % device)
    # Calculate the demodulator's magnitude and phase and add them to the sample
    # dict.
    sample["R"] = np.abs(sample["x"] + 1j * sample["y"])
    sample["phi"] = np.angle(sample["x"] + 1j * sample["y"])
    print(f"Measured RMS amplitude is {sample['R'][0]:.3e} V.")


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
