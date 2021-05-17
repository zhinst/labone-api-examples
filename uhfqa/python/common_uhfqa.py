""" Helper functions for UHFQA examples.
"""

# Copyright 2018 Zurich Instruments AG

import enum
import numpy as np


class ResultLoggingSource(enum.IntEnum):
    """Constants for selecting result logging source"""

    TRANS = 0
    THRES = 1
    ROT = 2
    TRANS_STAT = 3
    CORR_TRANS = 4
    CORR_THRES = 5
    CORR_STAT = 6


def initialize_device(daq, device):
    """Initialize device for UHFQA examples."""
    # General setup
    parameters = [
        # Input and output ranges
        ("sigins/*/range", 1.5),
        ("sigouts/*/range", 1.5),
        # Set termination to 50 Ohm
        ("sigins/*/imp50", 1),
        ("sigouts/*/imp50", 1),
        # Turn on both outputs
        ("sigouts/*/on", 1),
        # AWG in direct mode
        ("awgs/*/outputs/*/mode", 0),
        # DIO:
        # - output AWG waveform as digital pattern on DIO connector
        ("dios/0/mode", 2),
        # - drive DIO bits 15 .. 0
        ("dios/0/drive", 2),
        # Delay:
        ("qas/0/delay", 0),
        # Deskew:
        # - straight connection: sigin 1 -- channel 1, sigin 2 -- channel 2
        ("qas/0/deskew/rows/0/cols/0", 1),
        ("qas/0/deskew/rows/0/cols/1", 0),
        ("qas/0/deskew/rows/1/cols/0", 0),
        ("qas/0/deskew/rows/1/cols/1", 1),
        # Results:
        ("qas/0/result/length", 1.0),
        ("qas/0/result/averages", 0),
        ("qas/0/result/source", ResultLoggingSource.TRANS),
        # Statistics:
        ("qas/0/result/statistics/length", 1.0),
        # Monitor length:
        ("qas/0/monitor/length", 1024),
    ]

    # Number of readout channels
    num_readout_channels = 10

    # Rotation
    for i in range(num_readout_channels):
        parameters.append((f"qas/0/rotations/{i:d}", 1 + 0j))

    # Transformation
    # - no cross-coupling in the matrix multiplication (identity matrix)
    for i in range(num_readout_channels):
        for j in range(num_readout_channels):
            parameters.append((f"qas/0/crosstalk/rows/{i:d}/cols/{j:d}", int(i == j)))

    # Threshold
    for i in range(num_readout_channels):
        parameters.append((f"qas/0/thresholds/{i:d}/level", 1.0))

    # Update device
    daq.set([(f"/{device:s}/{node:s}", value) for node, value in parameters])

    # Set integration weights
    for i in range(num_readout_channels):
        weights = np.zeros(4096)
        daq.setVector(f"/{device:s}/qas/0/integration/weights/{i:d}/real", weights)
        daq.setVector(f"/{device:s}/qas/0/integration/weights/{i:d}/imag", weights)
    daq.setInt(f"/{device:s}/qas/0/integration/length", 1)


def acquisition_poll(daq, paths, num_samples, timeout=10.0):
    """Polls the UHFQA for data.

    Args:
        paths (list): list of subscribed paths
        num_samples (int): expected number of samples
        timeout (float): time in seconds before timeout Error is raised.
    """
    poll_length = 0.001  # s
    poll_timeout = 500  # ms
    poll_flags = 0
    poll_return_flat_dict = True

    # Keep list of recorded chunks of data for each subscribed path
    chunks = {p: [] for p in paths}
    gotem = {p: False for p in paths}

    # Poll data
    time = 0
    while time < timeout and not all(gotem.values()):
        dataset = daq.poll(poll_length, poll_timeout, poll_flags, poll_return_flat_dict)
        for path in paths:
            if path not in dataset:
                continue
            for data in dataset[path]:
                chunks[path].append(data["vector"])
                num_obtained = sum([len(x) for x in chunks[path]])
                if num_obtained >= num_samples:
                    gotem[path] = True
        time += poll_length

    if not all(gotem.values()):
        for path in paths:
            num_obtained = sum([len(x) for x in chunks[path]])
            print(f"Path {path}: Got {num_obtained} of {num_samples} samples")
        raise Exception(
            f"Timeout Error: Did not get all results within {timeout:.1f} s!"
        )

    # Return dict of flattened data
    return {p: np.concatenate(v) for p, v in chunks.items()}
