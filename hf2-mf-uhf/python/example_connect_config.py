# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to create an API session by connecting to a Data Server in order
to communicate with a Zurich Instruments device.
Connect to a Zurich Instruments device via the Data Server,
configure some settings on the instrument, obtain a single demodulator
sample via getSample(), calculate and add its RMS amplitude as a field to
the ``sample`` dictionary and return that dictionary.

Note:
  This is intended to be a simple example demonstrating how to connect to a
  Zurich Instruments device from Python. In most cases, data acquisition
  should use either ziDAQServer's poll() method or an instance of the
  ziDAQRecorder class, not the getSample() method.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * Signal output 1 conected to signal input 1 with a BNC cable.

Usage:
    example_connect_config.py [options] <device_id>
    example_connect_config.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: None]
    --hf2                     Flag if the used device is an HF2 instrument. (Since the HF2 uses
                              a different data server and support only API level 1
                              it requires minor tweaking) [default = False]
    -a --amplitude AMPLITUDE  The amplitude to set on the signal output. [default: 0.100]

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import numpy as np
import zhinst.utils


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = None,
    hf2: bool = False,
    amplitude: float = 0.100,
):
    """run the example."""

    apilevel_example = 1 if hf2 else 6  # The API level supported by this example.
    if not server_port:
        server_port = 8005 if hf2 else 8004
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all device configurations. The values below may be
    # changed if the instrument has multiple input/output channels and/or either
    # the Multifrequency or Multidemodulator options installed.
    out_channel = 0
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(props)
    in_channel = 0
    demod_index = 0
    osc_index = 0
    demod_rate = 10e3
    time_constant = 1e-6
    exp_setting = [
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        ["/%s/sigins/%d/range" % (device, in_channel), 2 * amplitude],
        ["/%s/demods/%d/enable" % (device, demod_index), 1],
        ["/%s/demods/%d/rate" % (device, demod_index), demod_rate],
        ["/%s/demods/%d/adcselect" % (device, demod_index), in_channel],
        ["/%s/demods/%d/order" % (device, demod_index), 4],
        ["/%s/demods/%d/timeconstant" % (device, demod_index), time_constant],
        ["/%s/demods/%d/oscselect" % (device, demod_index), osc_index],
        ["/%s/demods/%d/harmonic" % (device, demod_index), 1],
        ["/%s/oscs/%d/freq" % (device, osc_index), 400e3],
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), 1],
        [
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            amplitude,
        ],
    ]
    daq.set(exp_setting)

    # Wait for the demodulator filter to settle.
    time.sleep(10 * time_constant)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that the settings have taken effect on the device before issuing
    # the getSample() command. Note: the sync() must be issued after waiting for
    # the demodulator filter to settle above.
    daq.sync()

    # Obtain one demodulator sample via ziDAQServer's low-level getSample()
    # method - for extended data acquisition it's preferable to use
    # ziDAQServer's poll() method or the ziDAQRecorder class.
    sample = daq.getSample("/%s/demods/%d/sample" % (device, demod_index))
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
