""" Common helper functions used by the SHFQA examples
"""

# Copyright 2021 Zurich Instruments AG
import numpy as np


def generate_flat_top_gaussian(
    frequencies, pulse_duration, rise_fall_time, sampling_rate, scaling=0.9
):
    """Returns complex flat top Gaussian waveforms modulated with the given frequencies.

    Arguments:

        frequencies (array): array specifying the modulation frequencies applied to each
                             output wave Gaussian

        pulse_duration (float): total duration of each Gaussian in seconds

        rise_fall_time (float): rise-fall time of each Gaussian edge in seconds

        sampling_rate (float): sampling rate in samples per second based on which to
                               generate the waveforms

        scaling (optional float): scaling factor applied to the generated waveforms (<=1);
                                  use a scaling factor <= 0.9 to avoid overshoots

    Returns:

        pulses (dict): dictionary containing the flat top Gaussians as values

    """
    if scaling > 1:
        raise ValueError(
            "The scaling factor has to be <= 1 to ensure the generated waveforms lie within the \
                unit circle."
        )

    from scipy.signal import gaussian

    rise_fall_len = int(rise_fall_time * sampling_rate)
    pulse_len = int(pulse_duration * sampling_rate)

    std_dev = rise_fall_len // 10

    gauss = gaussian(2 * rise_fall_len, std_dev)
    flat_top_gaussian = np.ones(pulse_len)
    flat_top_gaussian[0:rise_fall_len] = gauss[0:rise_fall_len]
    flat_top_gaussian[-rise_fall_len:] = gauss[-rise_fall_len:]

    flat_top_gaussian *= scaling

    pulses = {}
    time_vec = np.linspace(0, pulse_duration, pulse_len)

    for i, f in enumerate(frequencies):
        pulses[i] = flat_top_gaussian * np.exp(2j * np.pi * f * time_vec)

    return pulses
