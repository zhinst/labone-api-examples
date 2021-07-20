# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments HDAWG and
use the precompensation module to fit filter parameters for a
measured signal

Connect to a Zurich Instruments HDAWG. The example uploads a signal to
the precompensationAdvisor module and reads back the filtered signal. This functionality
is used to feed a fitting algorithm for fitting filter parameters.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x HDAWG Instrument

Hardware configuration:
    Connect signal outputs 1 and 2 to signal inputs 1 and 2 with BNC cables.

Usage:
    example_awg_sourcefile.py [options] <device_id>
    example_awg_sourcefile.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: HDAWG]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]
    --no-plot              Hide plot of the recorded data.

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import numpy as np
import zhinst.ziPython
import zhinst.utils
from scipy import signal
from lmfit import Model
import matplotlib.pyplot as plt


def get_precompensated_signal(module_handle, input_signal, amplitude, timeconstant):
    """
    Uploads the input_signal to the precompensationAdvisor module and returns the
    simulated forward transformed signal with an exponential filter(amplitude,timeconstant).
    """
    module_handle.set("exponentials/0/amplitude", amplitude)
    module_handle.set("exponentials/0/timeconstant", timeconstant)
    module_handle.set("wave/input/inputvector", input_signal)
    return np.array(
        module_handle.get("wave/output/forwardwave", True)["/wave/output/forwardwave"][
            0
        ]["x"]
    )


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
):
    """run the example."""

    # Settings
    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    pre = daq.precompensationAdvisor()

    sampling_rate = 2.4e9

    x_val, target_signal = generate_target_signal(sampling_rate=sampling_rate)
    actual_signal = generate_actual_signal(target_signal, sampling_rate=sampling_rate)

    # prepare the precompensationAdvisor module
    pre.set("exponentials/0/enable", 1)
    pre.set("wave/input/source", 3)
    pre.set("device", device_id)
    daq.setDouble("/" + device_id + "/system/clocks/sampleclock/freq", sampling_rate)
    # a short pause is needed for the precompensationAdvisor module to read
    # the updated the sampling rate from the device node
    time.sleep(0.05)
    sampling_rate = pre.getDouble("samplingfreq")

    # Fitting the parameters
    gmodel = Model(
        get_precompensated_signal, independent_vars=["module_handle", "input_signal"]
    )
    result = gmodel.fit(
        target_signal,
        input_signal=actual_signal,
        module_handle=pre,
        amplitude=0.0,
        timeconstant=1e-4,
        fit_kws={"epsfcn": 1e-3},
    )  # 'epsfcn' is needed as filter parameters are discretized
    # in precompensationAdvisor module, otherwise fitting will
    # not converge

    print(result.fit_report())
    if plot:

        _, axis = plt.subplots()
        axis.plot(x_val, result.init_fit, "k", label="initial signal")
        axis.plot(x_val, result.best_fit, "r", label="fitted signal")
        axis.plot(x_val, target_signal, "b", label="target signal")
        axis.legend()
        axis.ticklabel_format(axis="both", style="sci", scilimits=(-2, 2))
        axis.set_xlabel("time [s]")
        axis.set_ylabel("Amplitude")
        plt.show()


def generate_target_signal(min_x=-96, max_x=5904, sampling_rate=2.4e9):
    """Returns a step function with given length and sampling interval."""
    x_values = np.array(range(min_x, max_x))
    x_values = [element / sampling_rate for element in x_values]
    signal2 = np.array(np.concatenate((np.zeros(-min_x), np.ones(max_x))))
    return x_values, signal2


def generate_actual_signal(initial_signal, amp=0.4, tau=100e-9, sampling_rate=2.4e9):
    """
    generate "actual signal" through filtering the initial signal with
    an exponential filter and add noise
    """

    # calculate a and b from amplitude and tau
    alpha = 1 - np.exp(-1 / (sampling_rate * tau * (1 + amp)))
    if amp >= 0.0:
        k = amp / (1 + amp - alpha)
        signal_a = [(1 - k + k * alpha), -(1 - k) * (1 - alpha)]
    else:
        k = -amp / (1 + amp) / (1 - alpha)
        signal_a = [(1 + k - k * alpha), -(1 + k) * (1 - alpha)]
    signal_b = [1, -(1 - alpha)]

    distorted_signal = np.array(
        signal.lfilter(signal_b, signal_a, initial_signal)
        + 0.01 * np.random.normal(size=initial_signal.size)
    )
    return distorted_signal


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
