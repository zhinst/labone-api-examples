function data = example_data_acquisition_grid_average(device_id)
% EXAMPLE_DATA_ACQUISITION_GRID_AVERAGE Record averaged data with the Data Acquisition Module in Grid Mode
%
% NOTE This example can only be ran on UHF and HF2 Instruments with the MF
% Option and MF Instruments with the MD Option enabled. The MF Option is not
% required to use the SW Trigger. However, this example is a stand-alone
% example that generates (by creating a beat in demodulator data) and captures
% it's own triggers. As such, it requires a simple feedback BNC cable between
% Signal Output 0 and Signal Input 0 of the device.
%
% USAGE DATA = EXAMPLE_DATA_ACQUISITION_GRID_AVERAGE(DEVICE_ID)
%
% Record demodulator sample data and align it in a 2D-matrix using a
% edge trigger using ziDAQ's ' dataAcquisitionModule' from the device
% specified by DEVICE_ID, e.g., 'dev1000' or 'uhf-dev1000'.
%
% The Data Acquisition Module implements software triggering analogously to
% the types of triggering found in spectroscopes. The Data Acquisition Module has
% a non-blocking (asynchronous) interface, it starts it's own thread to
% communicate with the data server.
%
% This example generates a bi-modal 'beat' in the demodulator signal in order
% to simulate 'events' in the demodulator data. Signal segments of these
% events are then recorded when the rising edge of the demodulator R value
% exceeds a certain threshold.
%
% The DAQ Module enables interpolation of the triggered data
% onto the specified columns of the grid and alignment of (num_rows)
% multiple triggers into the rows of the grid. This example
% demonstrates the averaging functionality of Grid Mode which is
% enabled when grid/repetitions is > 1 and
% grid/operation is set to average. The Data
% Acquisition Module triggers on different peaks in the bi-modal beat
% generated in the demodulator data (check the Plotter in the LabOne
% UI to see the original demod data) and the averaging operation
% averages the peaks caught by the trigger.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
%
% NOTE Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in your
% Matlab path. To do this (temporarily) for one Matlab session please navigate
% to the ziDAQ base folder containing the 'Driver', 'Examples' and 'Utils'
% subfolders and run the Matlab function ziAddPath().
% >>> ziAddPath;
%
% Use either of the commands:
% >>> help ziDAQ
% >>> doc ziDAQ
% in the Matlab command window to obtain help on all available ziDAQ commands.
%
% Copyright 2008-2018 Zurich Instruments AG

clear ziDAQ;

if ~exist('device_id', 'var')
    error(['No value for device_id specified. The first argument to the ' ...
           'example should be the device ID on which to run the example, ' ...
           'e.g. ''dev1000'' or ''uhf-dev1000''.'])
end

% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end

% The API level supported by this example.
supported_apilevel = 6;
% This example runs on any device type but requires either the Multifrequency
% or Multidemodulator option.
required_devtype = '.*';
required_options = {'MF|MFK|MD'};
required_err_msg = ['This example requires either an HF2/UHF Instrument ' ...
                    'with the Multifrequency (MF) Option installed or an MF ' ...
                    'Instrument with Multidemodulator (MD) Option installed. ' ...
                    'Note: The MF/MD Option is not a requirement to use the ' ...
                    'Data Acquisition Module itself, just to run this example.'];

% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, supported_apilevel, ...
                                     'required_devtype', '.*', ...
                                     'required_options', required_options, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
if ~any(strcmpi([branches], 'DEMODS'))
  data = [];
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

% Enable ziDAQ's logging, see the Programming Manual for location of the log files.
ziDAQ('setDebugLevel', 0);

% Define some helper parameters.
out_c = '0';
in_c = '0';
trigger_demod_index = 1;
trigger_demod_channel = '0';
% trigger_demod_idx is used to access the data in Matlab arrays and are therefore
% 1-based indexed. Node paths on the HF2/UHF use 0-based indexing.

amplitude = 0.100; % Signal output mixer amplitude, [V].
demod_rate = 50e3;
demod_order = 8;
demod_bandwidth = 10e3;

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the device ready for this experiment.
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 0);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/*'], 0);
if strfind(props.devicetype, 'HF2')
    ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
    ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
end
ziDAQ('setDouble', ['/' device '/demods/' trigger_demod_channel '/phaseshift'], 0);
for i=['0', '1', '2']
  demod_branch = ['/' device '/demods/' i];
  ziDAQ('setInt', [demod_branch, '/enable'], 1);
  ziDAQ('setDouble', [demod_branch, '/rate'], demod_rate);
end
% Ensure the configuration has taken effect before reading back the value actually set.
ziDAQ('sync');
demod_rate_set = ziDAQ('getDouble', ['/' device '/demods/' trigger_demod_channel '/rate']);
fprintf('Demod rate set (channel=0): %f.\n', demod_rate_set);

ziDAQ('setInt', ['/' device '/demods/*/harmonic'], 1);
ziDAQ('setInt', ['/' device '/demods/*/adcselect'], str2double(in_c));
ziDAQ('setInt', ['/' device '/demods/*/oscselect'], 0);

% Generate the beat in the demodulator data.
ziDAQ('setInt', ['/' device '/demods/0/oscselect'], 0);
ziDAQ('setInt', ['/' device '/demods/1/oscselect'], 1);  % requires MF option.
ziDAQ('setInt', ['/' device '/demods/2/oscselect'], 2);  % requires MF option.

% The difference between these oscs/{1,2}/freq and oscs/0/freq is smaller than
% the demodulator bandwdith we will configure - we will see the effect of the
% other oscillators in the output of demod/0.
ziDAQ('setDouble', ['/' device '/oscs/0/freq'], 400e3);        % [Hz]
ziDAQ('setDouble', ['/' device '/oscs/1/freq'], 400e3 +  50);  % [Hz]
ziDAQ('setDouble', ['/' device '/oscs/2/freq'], 400e3 + 523);  % [Hz]

ziDAQ('setInt', ['/' device '/sigouts/' out_c '/enables/0'], 1);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/enables/1'], 1);  % requires MF option.
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/enables/2'], 1);  % requires MF option.
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/0'], amplitude);  % requires MF option.
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/1'], amplitude);  % requires MF option.
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/2'], amplitude);  % requires MF option.

ziDAQ('setInt', ['/' device '/demods/*/order'], demod_order);
% A small timeconstant is required to see the interference between the
% demodulators
timeconstant = ziBW2TC(demod_bandwidth, demod_order);
ziDAQ('setDouble', ['/' device '/demods/0/timeconstant'], timeconstant);

% Flush all the buffers.
ziDAQ('sync');

% Create a Data Acquisition Module instance, the return argument is a handle to the module
% (thread).
h = ziDAQ('dataAcquisitionModule');

%% Configure the Data Acquisition Module
% Device on which trigger will be performed
ziDAQ('set', h, 'device', device)
%   type (int):
%     NO_TRIGGER = 0
%     EDGE_TRIGGER = 1
%     DIGITAL_TRIGGER = 2
%     PULSE_TRIGGER = 3
%     TRACKING_TRIGGER = 4
%     HW_TRIGGER = 6
%     TRACKING_PULSE_TRIGGER = 7
%     EVENT_COUNT_TRIGGER = 8
ziDAQ('set', h, 'type', 1);
%   triggernode (char):
%     Specify the trigger signal to trigger on. The trigger signal comprises
%     of a device node path appended with a trigger field seperated by a dot.
%     For demodulator samples, the following trigger fields are available:
%     SAMPLE.X = Demodulator X value
%     SAMPLE.Y = Demodulator Y value
%     SAMPLE.R = Demodulator Magnitude
%     SAMPLE.THETA = Demodulator Phase
%     SAMPLE.AUXIN0 = Auxilliary input 1 value
%     SAMPLE.AUXIN1 = Auxilliary input 2 value
%     SAMPLE.DIO = Digital I/O value
%     SAMPLE.TRIGINN = HW Trigger In N (where supported)
%     SAMPLE.TRIGOUTN = HW Trigger Out N (where supported)
%     SAMPLE.TRIGDEMOD1PHASE = Demod 1's oscillator's phase (MF, UHF)
%     SAMPLE.TRIGDEMOD2PHASE = Demod 2's oscillator's phase (MF)
%     SAMPLE.TRIGDEMOD4PHASE = Demod 4's oscillator's phase  (UHF)
%     SAMPLE.TRIGAWGTRIGN = AWG Trigger N  (where supported)
triggerpath = ['/' device '/demods/' trigger_demod_channel  '/sample'];
triggernode = [triggerpath '.r'];
% The dots in the signal paths are replaced by underscores in the data returned by MATLAB to
% prevent conflicts with the MATLAB syntax.
triggernode_us = [triggerpath '_r'];
ziDAQ('set', h, 'triggernode', triggernode);
%   edge (int):
%     Specify which edge type to trigger on.
%     POS_EDGE = 1
%     NEG_EDGE = 2
%     BOTH_EDGE = 3
ziDAQ('set', h, 'edge', 1)

ziDAQ('set', h, 'level', 0.04);
ziDAQ('set', h, 'hysteresis', 0.005);

% Unrequired parameters when type is EDGE_TRIGGER:
% ziDAQ('set', h, 'bitmask', 1)  % For DIGITAL_TRIGGER
% ziDAQ('set', h, 'bits', 1)  % For DIGITAL_TRIGGER
% ziDAQ('set', h, 'bandwidth', 10);  % For TRACKING_TRIGGER

% Data Acquisition Module Grid Mode configuration:
% grid/mode (int)
%   Enable/disable grid mode:
%     0: Disable grid mode.
%     1: Enable with nearest neighbour interpolation for the column data.
%     2: Enable with linear interpolation for the column data.
%     4: Adjust the duration so that the number of samples matches the
%     number of grid columns.
ziDAQ('set', h, 'grid/mode', 4);
% grid/repetitions (int)
%   The number of times to perform grid/operation.
num_repetitions = 30;
ziDAQ('set', h, 'grid/repetitions', num_repetitions);
% grid/cols (int)
%   Specify the number of columns in the grid's matrix. The data from each row
%   is interpolated onto a grid with the specified number of columns.
num_cols = 500;
ziDAQ('set', h, 'grid/cols', num_cols);
% grid/rows (int)
%   Specify the number of rows in the grid's matrix. Each row is the data
%   recorded from one trigger.
% The size of the internal buffer used to store data, this should be larger
% than trigger_duration.
trigger_duration = num_cols / demod_rate;  % [s]
ziDAQ('set', h, 'duration', trigger_duration);
trigger_delay = -0.5*trigger_duration;  % [s]
ziDAQ('set', h, 'delay', trigger_delay);
% Do not return overlapped trigger events.
ziDAQ('set', h, 'holdoff/time', trigger_duration);
ziDAQ('set', h, 'holdoff/count', 0);
num_rows = 60;
ziDAQ('set', h, 'grid/rows', num_rows);
% grid/direction (int)
%   Specify the ordering of the data stored in the grid's matrix.
%     0: Forward - the data in each row is ordered chronologically, e.g., the
%       first data point in each row corresponds to the first timestamp in the
%       trigger data.
%     1: Reverse - the data in each row is ordered reverse chronologically,
%       e.g., the first data point in each row corresponds to the last
%       timestamp in the trigger data.
%     2: Bidirectional - the ordering of the data alternates between Forward
%        and Backward ordering from row-to-row. The first row is Forward ordered.
ziDAQ('set', h, 'grid/direction', 0);

% The number of grids to record (if not running in endless mode). In grid
% mode, we will obtain count grids. The total number of total triggers
% that the module will record will be:
% n = count * grid/rows * grid/repetitions
num_grids = 1;
ziDAQ('set', h, 'count', num_grids);
ziDAQ('set', h, 'endless', 0);

%% Subscribe to the device node paths we would like to record when the trigger criteria is met.
signal_path = [triggernode '.avg'];
ziDAQ('subscribe', h, signal_path);
pid_error_stream_path = ['/' device '/pids/0/stream/error'];
node_paths = ziDAQ('listNodes', pid_error_stream_path, 7);
% If this node is present, then the instrument has the PID Option. In this
% case additionally subscribe to a PID's error. Note, PID streaming nodes not
% available on HF2 instruments.
if ~isempty(node_paths)
  ziDAQ('subscribe', h, pid_error_stream_path);
  ziDAQ('setDouble', ['/' device '/pids/0/stream/rate'], 30e3);
end
% Note: We subscribe to the trigger signal path last to ensure that we obtain
% complete data on the other paths (known limitation).
ziDAQ('subscribe', h, triggernode);

%% Start the module thread ready to receive triggers.
fprintf('calling execute()...\n');
ziDAQ('execute', h);
pause(1.2*ziDAQ('getDouble', h, 'buffersize'));

figure(1); clf;
t = linspace(trigger_delay, trigger_delay + trigger_duration, num_cols);
y = [0:num_rows-1];
[T, Y] = meshgrid(t, y);
subplot(2, 1, 1);
plot_handle(1) = mesh(T, Y, nan(size(T)));  % imagesc(T, Y, R)
title(sprintf('\\bf Averaged data over %d repetitions', num_repetitions));
xlabel('\bf Time, relative to trigger time (s)');
ylabel('\bf Grid row index');
zlabel('\bf Demod R (V)');
ch = colorbar();
colormap(winter(100));
subplot(2, 1, 2);
plot_handle(2) = plot(t, nan(size(t)));
title('\bf Averaged grid data plotted by timestamp.');
xlabel('\bf Device timestamp');
ylabel('\bf Demod R (V)');
timeout = 60; % [s]
maxZ = -inf;
minZ = inf;
t0 = tic;
num_finished_grids = 0;
flags = 0; % Initialize flags - 0th bit not set - not finished.
while ~ziDAQ('finished', h)
    pause(0.05);
    data = ziDAQ('read', h);
    if ~ziCheckPathInData(data, triggernode_us);
      fprintf('No update available since last read.\n');
    else
      % If count > 1 then more than one grid could be returned.
      num_grids = length(data.(device).demods(trigger_demod_index).sample_r_avg);
      for n=1:num_grids
        flags = data.(device).demods(trigger_demod_index).sample_r_avg{n}.header.flags;
        if bitand(flags, 1)
          % The first bit of flags is set to 1 when the grid is complete and the
          % configured number of operation repetitions have been formed.
          num_finished_grids = num_finished_grids + 1;
          fprintf('Finished grid %d of %d.\n', num_finished_grids, num_grids);
          % We could save the finished grid data here (if count > 1 and we
          % continue recording more grids...)
        end
        fprintf('Overall progress: %f. Grid %d has flags: %d.\n', ziDAQ('progress', h), ...
                num_finished_grids, flags);
      end
      figure(1);
      % Visualize the first grid's demodulator data (the demodulator used as
      % the trigger path).
      grid_index = 1;
      % Plot the updated grid.
      R = data.(device).demods(trigger_demod_index).sample_r_avg{grid_index}.value;
      maxR = max(R(:));
      minR = min(R(:));
      if minR < minZ; minZ = minR; end
      if maxR > maxZ; maxZ = maxR; end
      subplot(2, 1, 1);
      set(plot_handle(1), 'zData', R);
      zlim([minZ, maxZ]);
      caxis([minZ, maxZ]);
      subplot(2, 1, 2);
      xData = data.(device).demods(trigger_demod_index).sample_r{grid_index}.timestamp.';
      yData = R.';
      set(plot_handle(2), 'xData', xData(:), 'yData', yData(:));
      grid on;
      ylim([minZ, maxZ]);
    end
    % Check for timeout.
    if toc(t0) > timeout
      ziDAQ('finish', h);
      ziDAQ('clear', h);
      error('Failed to finish recording before timeout (%f seconds). Missing feedback cable between sigout 0 and sigin 0?', timeout);
    end
end
if ~bitand(flags, 1)
  % The Data Acquisition Module finished recording since performing the previous intermediate
  % read() in the loop: Do another read() to get the final data.
  fprintf('Data Acquisition Module finished since last intermediate read, reading out finished grid.\n');
  data = ziDAQ('read', h);
  % Here count is 1: Only one grid in data.
end

% Unsubscribe from all data in the module.
ziDAQ('unsubscribe', h, '*');
% Stop the module, delete the thread.
% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

assert(ziCheckPathInData(data, ['/' device '/demods/' trigger_demod_channel '/sample_r']), ...
       'Ooops, read() didn''t return the subscribed data - misconfig?');

end
