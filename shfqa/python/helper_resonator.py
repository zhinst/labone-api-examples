""" Helper functions for the SHFQA frequency sweep examples.
"""

# Copyright 2021 Zurich Instruments AG

import time
import numpy as np

from zhinst.deviceutils import SHFQA


def set_trigger_loopback(daq, dev):
    """
    Start a continuous trigger pulse from marker 1 A using the internal loopback to trigger in 1 A
    """

    m_ch = 0
    low_trig = 2
    continuous_trig = 1
    daq.setInt(f"/{dev}/raw/markers/*/testsource", low_trig)
    daq.sync()
    daq.setInt(f"/{dev}/raw/markers/{m_ch}/testsource", continuous_trig)
    daq.setDouble(f"/{dev}/raw/markers/{m_ch}/frequency", 1e3)
    daq.setInt(f"/{dev}/raw/triggers/{m_ch}/loopback", 1)
    time.sleep(0.2)


def clear_trigger_loopback(daq, dev):
    m_ch = 0
    daq.setInt(f"/{dev}/raw/markers/*/testsource", 0)
    daq.setInt(f"/{dev}/raw/triggers/{m_ch}/loopback", 0)


def measure_resonator_pulse_with_scope(
    daq,
    device_id,
    channel,
    trigger_input,
    pulse_length_seconds,
    envelope_delay=0,
    margin_seconds=400e-9,
):
    """Uses the scope to measure the pulse used for probing the resonator in pulsed spectroscopy.
    NOTE: this only works if the device under test transmits the signal at the
    selected center frequency. To obtain the actual pulse shape, the user must
    connect the output of the SHFQA back to the input on the same channel with
    a loopback cable.

    Arguments:
      daq (ziDAQServer): an instance of the ziPython.ziDAQServer class
        (representing an API session connected to a Data Server).

      device_id (str): the device's ID, this is the string that specifies the
        device's node branch in the data server's node tree.

      channel (int): the index of the SHFQA channel

      trigger_input (str): a string for selecting the trigger input
        Examples: "channel0_trigger_input0" or "software_trigger0"

      pulse_length_seconds (float): the length of the pulse to be measured in seconds

      envelope_delay (float): Time after the trigger that the OUT signal starts propagating

      margin_seconds (float): margin to add to the pulse length for the total length of the scope trace

    Returns:
      scope_trace (array): array containing the complex samples of the measured scope trace

    """

    scope_channel = 0
    print("Measure the generated pulse with the SHFQA scope.")
    segment_duration = pulse_length_seconds + margin_seconds
    shfqa = SHFQA(device_id, daq)
    shfqa.configure_scope(
        input_select={scope_channel: f"channel{channel}_signal_input"},
        num_samples=int(segment_duration * SHFQA.SAMPLING_FREQUENCY),
        trigger_input=trigger_input,
        num_segments=1,
        num_averages=1,
        trigger_delay=envelope_delay,
    )
    print("Measure the generated pulse with the SHFQA scope.")
    print(
        f"NOTE: Envelope delay ({envelope_delay *1e9:.0f} ns) is used as scope trigger delay"
    )

    shfqa.enable_scope()

    if trigger_input == "software_trigger0":
        # issue a signle trigger trigger
        daq.setInt(f"/{device_id}/SYSTEM/SWTRIGGERS/0/SINGLE", 1)

    scope_trace, *_ = shfqa.get_scope_data(time_out=5)
    return scope_trace[scope_channel]


def plot_resonator_pulse_scope_trace(scope_trace):
    """Plots the scope trace measured from the function `measure_resonator_pulse_with_scope`.

    Arguments:

        scope_trace (array): array containing the complex samples of the measured scope trace

    """

    import matplotlib.pyplot as plt

    time_ticks_us = 1.0e6 * np.array(range(len(scope_trace))) / SHFQA.SAMPLING_FREQUENCY
    plt.plot(time_ticks_us, np.real(scope_trace))
    plt.plot(time_ticks_us, np.imag(scope_trace))
    plt.title("Resonator probe pulse")
    plt.xlabel(r"t [$\mu$s]")
    plt.ylabel("scope samples [V]")
    plt.legend(["real", "imag"])
    plt.grid()
    plt.show()
