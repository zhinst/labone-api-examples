""" Helper functions for qubit readout examples
"""

# Copyright 2021 Zurich Instruments AG
import numpy as np


def generate_integration_weights(readout_pulses, rotation_angle=0):
    """Generates a dictionary with integration weights calculated as conjugates of the rotated
       readout pulses.

    Arguments:

        readout_pulses (dict): dictionary with items {waveform_slot : readout_pulse(array)}

        rotation_angle (optional float): angle by which to rotate the input pulses

    Returns:

        weights (dict): dictionary with items {waveform_slot: weights (array)}

    """

    weights = {}
    for waveform_slot, pulse in readout_pulses.items():
        weights[waveform_slot] = np.conj(pulse * np.exp(1j * rotation_angle))

    return weights


def generate_sequencer_program(num_measurements, task, waveform_slot=0):
    """Generates sequencer code for a given task.

    Arguments:

        num_measurements (int): number of measurements per qubit

        task (string): specifies the task the sequencer program will do
                       "dig_trigger_play_single": trigger a single waveform via dig trigger
                       "zsync_trigger_play_single": trigger a single waveform via zsync
                       "dig_trigger_play_all": trigger all waveforms via dig trigger
                       "zsync_trigger_play_all": trigger all waveforms via zsync

        waveform_slot (optional int): waveform slot to be played

    Returns:

        sequencer_program (string): sequencer program to be uploaded to the SHF

    """

    if task.lower() == "dig_trigger_play_single":
        return f"""
                repeat({num_measurements}) {{
                    waitDigTrigger(1);
                    startQA(QA_GEN_{waveform_slot}, 0x0, true,  0, 0x0);
                }}
                """
    if task.lower() == "zsync_trigger_play_single":
        return f"""
                repeat({num_measurements}) {{
                    waitZSyncTrigger();
                    startQA(QA_GEN_{waveform_slot}, 0x0, true,  0, 0x0);
                }}
                """
    if task.lower() == "dig_trigger_play_all":
        return f"""
                repeat({num_measurements}) {{
                    waitDigTrigger(1);
                    startQA(QA_GEN_ALL, QA_INT_ALL, true, 0, 0x0);
                }}
                """
    if task.lower() == "zsync_trigger_play_all":
        return f"""
                repeat({num_measurements}) {{
                    waitZSyncTrigger();
                    startQA(QA_GEN_ALL, QA_INT_ALL, true, 0, 0x0);
                }}
                """
    raise ValueError(
        f"Unsupported task: {task.lower()}. Please refer to the docstring for "
        f"more information on valid inputs."
    )


def plot_scope_data_for_weights(data, sampling_rate):
    """Plots the data measured with the scope for weight calculation.

    Arguments:

        data (array): data samples captured in a segmented scope shot, where the first half
                      corresponds to the ground state, second half to the excited state

        sampling_rate (float): sampling rate in samples per second used to compute the
                               time axis corresponding to the above data

    """
    import matplotlib.pyplot as plt

    split_data = np.split(data, 2)
    ground_state_data = split_data[0]
    excited_state_data = split_data[1]

    time_ticks = np.array(range(len(ground_state_data))) / sampling_rate

    fig = plt.figure(1)
    fig.suptitle("Scope measurement for readout weights")

    ax1 = plt.subplot(211)
    ax1.plot(time_ticks, np.real(ground_state_data))
    ax1.plot(time_ticks, np.imag(ground_state_data))
    ax1.set_title("ground state")
    ax1.set_ylabel("voltage [V]")
    plt.setp(ax1.get_xticklabels(), visible=False)
    ax1.xaxis.get_offset_text().set_visible(False)
    ax1.grid()
    plt.legend(["real", "imag"])

    ax2 = plt.subplot(212, sharex=ax1)
    ax2.plot(time_ticks, np.real(excited_state_data))
    ax2.plot(time_ticks, np.imag(excited_state_data))
    ax2.set_title("excited state")
    ax2.set_xlabel("t [s]")
    ax2.set_ylabel("voltage [V]")
    ax2.grid()

    plt.show()


def calculate_readout_weights(scope_data):
    """Calculates the weights from scope measurements for the excited and ground states.

    Arguments:

        data (array): data captured in a segmented scope shot;
            first half corresponds to the ground state, second half to the excited state

    Returns:

        weights (array): array containing the weights

    """

    split_data = np.split(scope_data, 2)
    return np.conj(split_data[1] - split_data[0])


def plot_readout_weights(weights, sampling_rate):
    """Plots the qubit readout weights.

    Arguments:

        weights (array): array containing the readout weights

    """

    import matplotlib.pyplot as plt

    time_ticks = np.array(range(len(weights))) / sampling_rate
    plt.plot(time_ticks, np.real(weights))
    plt.plot(time_ticks, np.imag(weights))
    plt.title("Qubit readout weights")
    plt.xlabel("t [s]")
    plt.ylabel("weights [V]")
    plt.legend(["real", "imag"])
    plt.grid()
    plt.show()


def plot_readout_results(data):
    """Plots the result data of a qubit readout as dots in the complex plane.

    Arguments:

      data (array): complex data to plot.

    """

    import matplotlib.pyplot as plt

    max_value = 0

    plt.rcParams["figure.figsize"] = [10, 10]

    for complex_number in data:
        real = np.real(complex_number)
        imag = np.imag(complex_number)

        plt.plot(real, imag, "x")

        max_value = max(max_value, max(abs(real)))
        max_value = max(max_value, max(abs(imag)))

    # zoom so that the origin is in the middle
    max_value *= 1.05
    plt.xlim([-max_value, max_value])
    plt.ylim([-max_value, max_value])

    plt.legend(range(len(data)))
    plt.title("qubit readout results")
    plt.xlabel("real part")
    plt.ylabel("imaginary part")
    plt.grid()
    plt.show()
