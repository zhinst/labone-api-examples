function [data] = example_data_acquisition_grid(device_id, varargin)
% EXAMPLE_DATA_ACQUISITION_GRID Record data using a demodulator trigger via ziDAQ's Data Acquisition module
%
% USAGE DATA = EXAMPLE_DATA_ACQUISITION_GRID(DEVICE_ID)
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
% The DAQ Module enables interpolation of the triggered data onto
% the specified columns of the grid and alignment of (num_rows)
% multiple triggers into the rows of the grid. This example
% demonstrates basic Grid Mode usage without an addition operation,
% e.g., averaging, on the recorded data (grid/operation is 0).
%
% This example records the demodulator data as is - essentially a constant
% value with noise. The Data Acquisition Module's 'find' functionality calculates an
% appropriate trigger level to record triggers using an edge trigger.
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
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, supported_apilevel);
ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
if ~any(strcmpi([branches], 'DEMODS'))
  data = [];
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

% Enable ziDAQ's logging, see the Programming Manual for location of the log files.
ziDAQ('setDebugLevel', 0);

% Parse the optional varargin.
p = inputParser;
isnonnegscalar = @(x) isnumeric(x) && isscalar(x) && (x > 0);
% The number of Data Acquisition Module grids to record.
p.addParamValue('num_grids', 3, isnonnegscalar);
p.parse(varargin{:});
num_grids = p.Results.num_grids;

% Define some helper parameters.
out_c = '0';
out_mixer_c_0 = ziGetDefaultSigoutMixerChannel(props, 0);
in_c = '0';
trigger_demod_index = 1;
trigger_demod_channel = '0';
% trigger_demod_index is used to access the data in Matlab arrays and are therefore
% 1-based indexed. Node paths on the HF2/UHF use 0-based indexing.

amplitude = 0.100; % Signal output mixer amplitude, [V].
demod_rate = 50e3;
demod_bandwidth = 10e3;
demod_order = 4;
timeconstant = ziBW2TC(demod_bandwidth, demod_order);

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the device ready for this experiment.
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 0);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2*amplitude);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/*'], 0);
if strfind(props.devicetype, 'HF2')
    ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
    ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
end
ziDAQ('setDouble', ['/' device '/demods/*/phaseshift'], 0);
ziDAQ('setDouble', ['/' device '/demods/' trigger_demod_channel '/rate'], demod_rate);
ziDAQ('setInt', ['/' device '/demods/' trigger_demod_channel '/enable'], 1);
% Ensure the configuration has taken effect before reading back the value actually set.
ziDAQ('sync');
demod_rate_set = ziDAQ('getDouble', ['/' device '/demods/' trigger_demod_channel '/rate']);
fprintf('Demod rate set (channel=0): %f.\n', demod_rate_set);
ziDAQ('setInt', ['/' device '/demods/*/harmonic'], 1);
ziDAQ('setInt', ['/' device '/demods/*/adcselect'], str2double(in_c));
ziDAQ('setInt', ['/' device '/demods/*/oscselect'], 0);
ziDAQ('setInt', ['/' device '/demods/*/order'], demod_order);
ziDAQ('setDouble', ['/' device '/demods/' trigger_demod_channel '/timeconstant'], timeconstant);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c_0], amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c_0], 1);

% Flush all the buffers.
ziDAQ('sync');
timeconstant_set = ziDAQ('getDouble', ['/' device '/demods/' trigger_demod_channel '/timeconstant']);

% Wait for the demodulator filter to settle
pause(20*timeconstant_set);

% Create a Data Acquisition Module instance, the return argument is a handle to the module
% (thread).
h = ziDAQ('dataAcquisitionModule');

%% Configure the Data Acquisition Module
% Device on which trigger will be performed
ziDAQ('set', h, 'device', device)
ziDAQ('set', h, 'endless', 0);
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
ziDAQ('set', h, 'edge', 1);
% Note: We do not manually set level and hysteresis in
% this example, rather we set the findlevel parameter to 1 and let
% the Data Acquisition Module determine an appropriate level and hysteresis for us.
% level (double):
%   The threshold upon which to trigger.
% ziDAQ('set', h, 'level', 0.100);
% hysteresis (double):
%   The hysterisis is effectively a second criteria (if non-zero) for
%   triggering and makes triggering more robust in noisy signals. When the
%   trigger `level` is violated, then the signal must return beneath (for
%   positive trigger edge) the hysteresis value in order to trigger.
% ziDAQ('set', h, 'hysteresis', 0.005);

% The size of the internal buffer used to store data, this should be larger
% than trigger_duration.
% Unrequired parameters when type is EDGE_TRIGGER:
% ziDAQ('set', h, 'bitmask', 1)  % For DIGITAL_TRIGGER
% ziDAQ('set', h, 'bits', 1)  % For DIGITAL_TRIGGER
% ziDAQ('set', h, 'bandwidth', 10);  % For TRACKING_TRIGGER

% Data Acquisition Module Grid Mode configuration:
% grid/mode (int)
%   Enable/disable grid mode:
%     1: Enable with nearest neighbour interpolation for the column data.
%     2: Enable with linear interpolation for the column data.
%     4: Enable exact grid mode. The duration is adjusted to aligned exactly with the number of grid columns.
ziDAQ('set', h, 'grid/mode', 4);
% Note: grid/operation is not relevant if repetitions is 1, see
% below.
% grid/operation (int)
%   If the number of repetitions > 1, either replace or average the data in
%     the grid:
%     0: Replace.
%     1: Average.
% ziDAQ('set', h, 'grid/operation', 1);
% grid/repetitions (int)
%   The number of times to perform grid/operation.
num_repetitions = 1;
ziDAQ('set', h, 'grid/repetitions', num_repetitions);
% grid/cols (int)
%   Specify the number of columns in the grid's matrix. The data from each row
%   is interpolated onto a grid with the specified number of columns.
num_cols = 500;
% Set exact grid mode. This is the most suitable mode for FFTs
% Calculate the length of each trigger (in seconds). The duration can be calculated
% from the demodulator sampling rate and the number of grid columns
trigger_duration = num_cols / demod_rate;
trigger_delay = -0.25*trigger_duration;  % [s]
ziDAQ('set', h, 'delay', trigger_delay);
ziDAQ('set', h, 'grid/cols', num_cols);
% Do not return overlapped trigger events.
ziDAQ('set', h, 'holdoff/time', trigger_duration);
ziDAQ('set', h, 'holdoff/count', 0);

% grid/rows (int)
%   Specify the number of rows in the grid's matrix. Each row is the data
%   recorded from one trigger.
num_rows = 500;
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
ziDAQ('set', h, 'count', num_grids);

%% Subscribe to the device node paths we would like to record when the trigger criteria is met.
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
% complete data on the other paths (known limitation). We must subscribe to
% the trigger signal path.
ziDAQ('subscribe', h, triggernode);

% We will perform intermediate reads from the module. When a grid is complete
% and read() is called, the data is removed from the module. We have to manage
% saving of the finished grid ourselves if we perform intermediate reads.
data = struct();
data.(device).pids.stream.error = {};
data.(device).demods.sample_r = {};

%% Start recording
% Start the module's thread -> ready to be triggered.
ziDAQ('set', h, 'enable', 1);
% Tell the Data Acquisition Module to determine the trigger level.
ziDAQ('set', h, 'findlevel', 1);
findlevel = 1;
timeout = 10;  % [s]
t0 = tic;
while (findlevel == 1)
  pause(0.05);
  findlevel = ziDAQ('getInt', h, 'findlevel');
  if toc(t0) > timeout
    ziDAQ('finish', h);
    ziDAQ('clear', h);
    error('Data Acquisition Module didn''t find a trigger level after %.3f seconds.\n', timeout)
  end
end
level = ziDAQ('getDouble', h, 'level');
hysteresis = ziDAQ('getDouble', h, 'hysteresis');
fprintf('Found and set level: %.3e, hysteresis: %.3e\n', level, hysteresis);

figure(1); clf;
t = linspace(trigger_delay, trigger_delay + trigger_duration, num_cols);
y = [0:num_rows-1];
subplot(2, 1, 1);
plot_handle(1) = imagesc(t, y, nan(size(length(t), length(y))));
title(sprintf('\\bf Demod Grid Data plotted as a Matrix'));
xlabel('\bf Time, relative to trigger (s)');
ylabel('\bf Grid row index');
zlabel('\bf Demod R (V)');
colormap(winter(100));
colorbar();
subplot(2, 1, 2);
plot_handle(2) = plot(t, nan(size(t)));
title('\bf Grid Data plotted by timestamp.');
xlabel('\bf Device timestamp');
ylabel('\bf Demod R (V)');
maxZ = -inf;
minZ = inf;
num_finished_grids = 0;
timeout = 120; % [s]
t0 = tic;
flags = [];
while ~ziDAQ('finished', h)
    pause(0.05);
    data_read = ziDAQ('read', h);
    if ~ziCheckPathInData(data_read, triggernode_us)
      fprintf('No update available since last read.\n');
    else
      % If count > 1 then more than one grid could be returned.
      num_grids_read = length(data_read.(device).demods(trigger_demod_index).sample_r);
      for n=1:num_grids_read
        flags = data_read.(device).demods(trigger_demod_index).sample_r{n}.header.flags;
        if bitand(flags, 1)
          % The first bit of flags is set to 1 when the grid is complete and the
          % configured number of operation repetitions have been formed.
          num_finished_grids = num_finished_grids + 1;
          fprintf('Finished grid %d of %d.\n', num_finished_grids, num_grids);
          data.(device).demods.sample_r{end+1} = data_read.(device).demods(trigger_demod_index).sample_r{n};
          if ziCheckPathInData(data_read, pid_error_stream_path)
            % We only get this data if the (non-HF2) device has the PID Option.
            data.(device).pids.stream.error{end+1} = data_read.(device).pids.stream.error{n};
          end
          subplot(2, 1, 2); set(plot_handle(2), 'xData', [], 'yData', []);
        end
        fprintf('Overall progress: %f. Grid %d flags: %d.\n', ziDAQ('progress', h), num_finished_grids, flags);
      end
      % Visualize the last grid's demodulator data (the demodulator used as
      % the trigger path) from the intermediate read(). Plot the updated
      % grid.
      R = data_read.(device).demods(trigger_demod_index).sample_r{end}.value;
      maxR = max(R(:));
      minR = min(R(:));
      if minR < minZ; minZ = minR; end
      if maxR > maxZ; maxZ = maxR; end
      update_plot(plot_handle, R , data_read.(device).demods(trigger_demod_index).sample_r{end}.timestamp, minZ, maxZ);
    end
    if toc(t0) > timeout
        % If for some reason we're not obtaining triggers quickly enough, the
        % following command will force the end of the recording.
        if num_finished_grids == 0
            ziDAQ('finish', h);
            ziDAQ('clear', h);
            error('Failed to record any completed grids before timeout (%d seconds). Missing feedback cable between sigout 0 and sigin 0?', timeout);
        else
            fprintf('Recorded %d triggers. Loop timeout (%.2f s) before acquiring %d triggers\n');
            fprintf('Increase loop `timeout` to record more.\n', num_triggers, timeout, trigger_count);
        end
    end
end

if ~bitand(flags, 1)
  % The Data Acquisition Module finished recording since performing the previous intermediate
  % read() in the loop: Do another read() to get the final data.
  fprintf('Data Acquisition Module finished since last intermediate read() in loop, reading out finished grid(s).\n');
  data_read = ziDAQ('read', h);
  num_grids = length(data_read.(device).demods(trigger_demod_index).sample_r);
  for n=1:num_grids
    flags = data_read.(device).demods(trigger_demod_index).sample_r{n}.header.flags;
    if flags & 1
      data.(device).demods.sample_r{end+1} = data_read.(device).demods(trigger_demod_index).sample_r{n};
      if ziCheckPathInData(data_read, pid_error_stream_path)
        % We only get this data if the (non-HF2) device has the PID Option.
        data.(device).pids.stream.error{end+1} = data_read.(device).pids.stream.error{n};
      end
    end
  end
  R = data_read.(device).demods(trigger_demod_index).sample_r{end}.value;
  update_plot(plot_handle, R , data_read.(device).demods(trigger_demod_index).sample_r{end}.timestamp, minZ, maxZ);
end

% Unsubscribe from all data in the module.
ziDAQ('unsubscribe', h, '*');
% Stop the module, delete the thread.
% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

assert(ziCheckPathInData(data, triggernode_us), 'Ooops, read() didn''t return the subscribed data - misconfig?');

end

function update_plot(plot_handle, R, timestamp, minZ, maxZ)
  figure(1);
  subplot(2, 1, 1);
  set(plot_handle(1), 'cData', R);
  caxis([minZ, maxZ]);
  axis tight;
  subplot(2, 1, 2);
  xData = timestamp.';
  yData = R.';
  set(plot_handle(2), 'xData', xData(:), 'yData', yData(:));
  grid on;
  ylim([minZ, maxZ]);
end
