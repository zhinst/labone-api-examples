function [data_no_trig, data_trig, data_fft] = hf2_example_scope(device_id, varargin)
% HF2_EXAMPLE_SCOPE record scope data using the Scope Module
%
% USAGE SCOPE_SHOTS = HF2_EXAMPLE_SCOPE(DEVICE_ID)
%
% Get assembled scope shots from the device specified by DEVICE_ID using
% the Scope Module. DEVICE_ID should be a string, e.g.,
% 'dev1000' or 'uhf-dev1000'.
%
% REQUIRES a BNC cable between the signal input and output channels the scope
% is configured for.
%
% DATA = HF2_EXAMPLE_SCOPE(DEVICE_ID, VARARGIN)
%
% Provide optional input arguments to the example via a MATLAB
% variable length input argument list, see the inline documentation in
% the run_example() function below for a description of the possible
% input arguments.
%
% NOTE This example can only be ran on HF2 Instruments.
%
% NOTE This example uses API level 1; users of other device classes are
% recommended to connect via API level 6, particularly when obtaining scope
% data.
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
           'e.g. ''dev1000'' or ''hf2-dev1000''.'])
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
apilevel_example = 1;
% Create an API session; connect to the correct Data Server for the device.
required_err_msg = 'This example only runs with HF2 Instruments.';
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'HF2', ...
                                     'required_options', {}, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

% Enable the API's log.
ziDAQ('setDebugLevel', 0);

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
isnonneg = @(x) isnumeric(x) && isscalar(x) && (x > 0);
scope_channels = [0, 1, 2, 3];
is_scope_channel = @(x) assert(ismember(x, scope_channels), ...
                               'Invalid value for scope_channel: %d. Valid values: %s.', x, mat2str(scope_channels));
% The scope's input channel; The value 2 corresponds to Signal Output 0.
p.addParamValue('scope_channel', 2, is_scope_channel);
% The threshold level to trigger the sending of scope shots from the device
% (in physical units, [V]). Important: This must be converted to a 16-bit
% signed integer when passed to the scope's `triglevel` parameter. See scope
% configuration below for more details.
p.addParamValue('trigger_level', 0.0, @isnumeric);
% The signal output range, [V].
p.addParamValue('amplitude', 0.5, @isnumeric);
% NOTE The Signal Output and Input ranges are relevant since they're required for
% correct scaling of the scope's wave node value.
% The length of time to accumulate subscribed data (by sleeping) before polling a second time [s].
p.addParamValue('sigout_range', 1.0, @isnumeric);
% The signal output mixer amplitude, [V].
p.addParamValue('sigin_range', 1.0, isnonneg);
p.parse(varargin{:});

if p.Results.trigger_level >= p.Results.amplitude
    warning(sprintf(['Specified trigger_level (%.3f V) >= signal output ' ...
                     'amplitude (%.3f V), scope will not be triggered when measuring ' ...
                     'via a simple feedback cable between signal inputs and signal ' ...
                     'outputs.'], p.Results.trigger_level, p.Results.amplitude));
end

%% Define some other derived and helper parameters.
switch p.Results.scope_channel
% Select the instrument hardware Signal Output and Input channels to configure
% based on the configured scope channel.
  case {0, 2}
    % Use Signal Output/Inputs 0
    out_c = '0';  % Signal output channel
    in_c = '0';  % Signal input channel
  case {1, 3}
    % Use Signal Output/Inputs 1
    out_c = '1';  % Signal output channel
    in_c = '1';  % Signal input channel
  otherwise
    error('Invalid scope channel: %d.\n', p.Results.scope_channel);
end
% Get the value of the instrument's default Signal Output mixer channel.
out_mixer_c = num2str(ziGetDefaultSigoutMixerChannel(props, str2num(out_c)));
osc_c = '0';  % The instrument's oscillator channel to use.

frequency = 1.0e6;

% The scope's sampling rate is configured by specifying the ``time`` node
% (/devN/scopes/0/time). The rate is equal to 210e6/2**time, where 210e6
% is the HF2 ADC's sampling rate (^=clockbase, /devX/clockbase). time is
% an integer in range(0, 16).
%
% Since the length of a scope shot is fixed (2048) on an HF2, specifying
% the rate also specifies the time duration of a scope shot,
% t_shot=2048*1./rate=2048*2**time/210e6.
SCOPE_SHOT_LENGTH = 2048;

% Therefore, if we would like to obtain (at least) 10 periods of the
% signal generated by Oscillator 1, we need to set the scope's time
% parameter as following:
clockbase = double(ziDAQ('getInt', ['/' device '/clockbase'])); % 210e6 for HF2
desired_t_shot = 10/frequency;
scope_time = ceil(max([0, log2(clockbase*desired_t_shot/SCOPE_SHOT_LENGTH)]));
if scope_time > 15
  scope_time = 15;
  warning(['Can''t not obtain scope durations of %.3f s, scope shot duration ' ...
           'will be %.3f.'], desired_t_shot, 2048*2^scope_time/clockbase);
end
fprintf('Will set /%s/scopes/0/time to %d.\n', device, scope_time);

%% Configure the HF2
% Output settings
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], p.Results.sigout_range);
ziDAQ('setInt', ['/' device '/sigouts/*/enables/*'], 0);
ziDAQ('setDouble', ['/' device '/sigouts/*/amplitudes/*'], 0.000);

ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c], p.Results.amplitude/p.Results.sigout_range);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c], 1);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);

% Input settings
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], p.Results.sigin_range);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/ac'], 1);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/diff'], 0);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/imp50'], 0);

% Oscillator settings
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], frequency);

% Scope settings
ziDAQ('setInt', ['/' device '/scopes/0/channel'], p.Results.scope_channel);
% Disable scope triggering.
ziDAQ('setInt', ['/' device '/scopes/0/trigchannel'], -1);
ziDAQ('setDouble', ['/' device '/scopes/0/trigholdoff'], 0.1);

ziDAQ('setDouble', ['/' device '/scopes/0/trigholdoff'], 0.1);
% Turn on bandwidth limiting: avoid antialiasing effects due to subsampling
% when the scope sample rate is less than the input channel's sample rate.
ziDAQ('setInt', ['/' device '/scopes/0/bwlimit'], 1);
ziDAQ('setInt', ['/' device '/scopes/0/time'], scope_time); % set the sampling rate

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``poll`` command and clear the API's data buffers to remove any old data.
ziDAQ('sync');

% Initialize and configure the Scope Module.
scopeModule = ziDAQ('scopeModule');
% 'mode' : Scope data processing mode.
% 0 - Pass through scope segments assembled, returned unprocessed,
%     non-interleaved.
% 1 - Time domain with averaging, scope recording assembled, scaling applied, averaged, if averaging is
%     enabled, using the method set by 'averager/method'.
% 2 - Not yet supported.
% 3 - As for mode 1, except an FFT is applied to every segment of the scope
%     recording.
ziDAQ('set', scopeModule, 'mode', 1);
% 'averager/method' : Averaging method to use.
%   0 - exponential averaging using the weight specified by 'averager/weight'.
%   1 - uniform averaging. The 'averager/weight' value has no effect but must be greater than 1 to enable everaging.
ziDAQ('set', scopeModule, 'averager/method', 0)
% 'averager/weight' : Averager behaviour for exponential averaging method.
%   weight=1 - don't average.
%   weight>1 - average the scope record segments using an exponentially weighted moving average.
ziDAQ('set', scopeModule, 'averager/weight', 10);
% 'averager/enable' : Activate averaging
%   0 - disabled
%   1 - enabled
ziDAQ('set', scopeModule, 'averager/enable', 0);
% 'historylength' : The number of scope records to keep in
%   the Scope Module's memory, when more records arrive in the Module
%   from the device the oldest records are overwritten.
module_historylength = 20;
ziDAQ('set', scopeModule, 'historylength', 20);

if p.Results.scope_channel == 0
  externalscaling = ziDAQ('getDouble', ['/' device, '/sigins/0/range']);
elseif p.Results.scope_channel == 1
  externalscaling = ziDAQ('getDouble', ['/' device, '/sigins/1/range']);
elseif p.Results.scope_channel == 2
  externalscaling = ziDAQ('getDouble', ['/', device, '/sigouts/0/range']);
elseif p.Results.scope_channel == 3
  externalscaling = ziDAQ('getDouble', ['/', device, '/sigouts/1/range']);
else
  error(['Invalid value for scope channel (', num2str(p.Results.scope_channel), '). '
         'The HF2 scope only supports signal inputs and outputs. Use 0, 1, 2 or 3 instead.']);
end
ziDAQ('set', scopeModule, 'externalscaling', externalscaling)

% Subscribe to the scope's data in the module.
wave_nodepath = ['/' device '/scopes/0/wave'];
ziDAQ('subscribe', scopeModule, wave_nodepath);

min_num_records = 20;
fprintf('Obtaining FFT scope data with triggering disabled...\n')
data_no_trig = getScopeRecords(device, scopeModule, min_num_records);
if ziCheckPathInData(data_no_trig, wave_nodepath)
  checkScopeRecordFlags(data_no_trig.(device).scopes(1).wave);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Configure the scope and obtain data with triggering enabled.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ziDAQ('setInt', ['/' device '/scopes/0/trigchannel'], p.Results.scope_channel);
% NOTE The scope 'triglevel' parameter is not defined using the physical units
% of the scope input channel; It is defined according to values of the data
% returned by the scope. Scope shots consist of values which are 16-bit signed
% integers and the trigger level is defined as integer accordingly in the
% range [-2^15, 2^15].
scope_triglevel = p.Results.trigger_level*2^15;
ziDAQ('setDouble', ['/' device '/scopes/0/triglevel'], scope_triglevel);
ziDAQ('setDouble', ['/' device '/scopes/0/trigholdoff'], 0.1);

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``poll`` command and clear the API's data buffers to remove any old data.
ziDAQ('sync');

% Enable the scope and read the scope data arriving from the device. Note: The
% module is already configured and the required data is already subscribed from
% above.
fprintf('Obtaining scope data with triggering enabled...\n')
data_trig = getScopeRecords(device, scopeModule, min_num_records);
if ziCheckPathInData(data_trig, wave_nodepath)
  checkScopeRecordFlags(data_trig.(device).scopes(1).wave);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%    # Configure the Scope Module to calculate FFT data
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Set the Scope Module's mode to return frequency domain data.
ziDAQ('set', scopeModule, 'mode', 3);
% Use a Hann window function.
ziDAQ('set', scopeModule, 'fft/window', 1);

% Enable the scope and read the scope data arriving from the device; the Scope
% Module will additionally perform an FFT on the data. Note: The other module
% parameters are already configured and the required data is already subscribed
% from above.
fprintf('Obtaining FFT scope data with triggering enabled...\n')
data_fft = getScopeRecords(device, scopeModule, min_num_records);
if ziCheckPathInData(data_fft, wave_nodepath)
  checkScopeRecordFlags(data_fft.(device).scopes(1).wave);
end

% Stop the scope module.
ziDAQ('finish', scopeModule);

% Clear the module's thread. It may not be used again.
% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', scopeModule);

clockbase = ziDAQ('getInt', ['/' device '/clockbase']);

% Plot the scope data with triggering disabled.
figure(1); clf;
subplot(2, 1, 1);
num_records_no_trig = 0;
if ziCheckPathInData(data_no_trig, ['/' device '/scopes/0/wave']);
  records_no_trig = data_no_trig.(device).scopes(1).wave;
  num_records_no_trig = length(records_no_trig);
  plotScopeRecords(records_no_trig, scope_time, clockbase);
end
title('\bf Scope records (triggering disabled)');
grid on;
box on;
axis tight;
xlabel('t (us)');
fprintf('Number of scope records with triggering disabled: %d.\n', length(records_no_trig));

% Plot the scope data with triggering enabled.
subplot(2, 1, 2);
num_records_trig = 0;
if ziCheckPathInData(data_trig, ['/' device '/scopes/0/wave']);
  records_trig = data_trig.(device).scopes(1).wave;
  num_records_trig = length(records_trig);
  plotScopeRecords(records_trig, scope_time, clockbase);
end
title('\bf Scope records (triggering enabled)');
grid on;
box on;
axis tight;
xlabel('t (us)');
fprintf('Number of scope records with triggering enabled: %d.\n', length(records_trig));

% Plot the FFT'd scope data with triggering disabled.
figure(2); clf;
num_records_fft = 0;
if ziCheckPathInData(data_fft, ['/' device '/scopes/0/wave']);
  records_fft = data_fft.(device).scopes(1).wave;
  num_records_fft = length(records_fft);
  plotScopeRecords(records_fft, scope_time, clockbase);
end
title('\bf FFT of Scope records (triggering enabled)');
grid on;
box on;
xlabel('Frequency (Hz)');
fprintf('Number of scope records with triggering disabled (and FFT''d): %d.\n', num_records_fft);

end

function data = getScopeRecords(device, scopeModule, num_records)
% GETSCOPERECORDS  Obtaining scope records from device using an Scope Module.

  % Tell the module to be ready to acquire data; reset the module's progress to 0.0.
  ziDAQ('execute', scopeModule);

  % Enable the scope: Now the scope is ready to record data upon
  % receiving triggers.
  ziDAQ('setInt', ['/' device '/scopes/0/enable'], 1);
  ziDAQ('sync');

  time_start = tic;
  timeout = 30;  % [s]
  records = 0;
  % Wait until the Scope Module has received and processed the desired number of records.
  while records < num_records
    pause(0.5)
    records = ziDAQ('getInt', scopeModule, 'records');
    progress = ziDAQ('progress', scopeModule);
    fprintf(['Scope module has acquired %d records (requested %d). ' ...
             'Progress of current segment %.1f %%.\n'], records, ...
            num_records, 100*progress);
    % Advanced use: It's possible to read-out data before all records have
    % been recorded (or even all segments in a multi-segment record
    % have been recorded). Note that complete records are removed
    % from the Scope Module and can not be read out again; the
    % read-out data must be managed by the client code. If a
    % multi-segment record is read-out before all segments have been
    % recorded, the wave data has the same size as the complete data
    % and scope data points currently unacquired segments are equal
    % to 0.
    %
    % data = ziDAQ('read', scopeModule);
    % wave_nodepath = ['/' device '/scopes/0/wave'];
    % if wave_nodepath in data:
    %   Do something with the data...
    if toc(time_start) > timeout
      % Break out of the loop if for some reason we're no longer receiving
      % scope data from the device.
      fprintf('\nScope Module did not return %d records after %f s - forcing stop.', num_records, timeout);
      break
    end
  end
  ziDAQ('setInt', ['/' device '/scopes/0/enable'], 0);

  % Read out the scope data from the module.
  data = ziDAQ('read', scopeModule);

  % Stop the module; to use it again we need to call execute().
  ziDAQ('finish', scopeModule);

end

function plotScopeRecords(scope_records, scope_time, clockbase)
% plotScopeRecords Plot the scope records.
  num_records = length(scope_records);
  c = hsv(num_records);
  for ii=1:num_records
    totalsamples = double(scope_records{ii}.totalsamples);
    if ~bitand(scope_records{ii}.channelmath(1), 2)
      dt = scope_records{ii}.dt;
      % Note, triggertimestamp and the timestamp always have the same value on HF2.
      t = linspace(0, totalsamples, totalsamples)*dt;
      plot(1e6*t, scope_records{ii}.wave, 'color', c(ii, :));
      hold on;
      plot([0.0, 0.0], get(gca, 'ylim'), '--k');
    elseif bitand(scope_records{ii}.channelmath(1), 2)
      scope_rate = double(clockbase)/2^scope_time;
      f = linspace(0, scope_rate/2, totalsamples);
      semilogy(f/1e6, scope_records{ii}.wave, 'color', c(ii, :));
      hold on;
    end
  end
  ylabel('Amplitude (V)');
end

function checkScopeRecordFlags(scope_records)
% CHECKSCOPERECORDFLAGS report if the scope records contain corrupt data
%
% CHECKSCOPERECORDFLAGS(SCOPE_RECORDS)
%
%   Loop over all records and print a warning to the console if an error bit in
%   flags has been set.
  num_records = length(scope_records);
  for ii=1:num_records
    if bitand(scope_records{ii}.flags, 1)
      fprintf('Warning: Scope record %d/%d flag indicates dataloss.', ii, num_records);
    end
    if bitand(scope_records{ii}.flags, 2)
      fprintf('Warning: Scope record %d/%d indicates missed trigger.', ii, num_records);
    end
    if bitand(scope_records{ii}.flags, 3)
      fprintf('Warning: Scope record %d/%d indicates transfer failure (corrupt data).', ii, num_records);
    end
    totalsamples = scope_records{ii}.totalsamples;
    for cc=1:size(scope_records{ii}.wave, 2)
      % Check that the wave in each scope channel contains the expected number of samples.
      assert(length(scope_records{ii}.wave(:, cc)) == totalsamples, ...
             'Scope record %d/%d size does not match totalsamples.', ii, num_records);
    end
  end
end
