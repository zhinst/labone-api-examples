function [data_no_trig, data_trig, data_fft] = example_scope(device_id)
% EXAMPLE_SCOPE record scope data using the Scope Module
%
% USAGE SCOPE_SHOTS = EXAMPLE_SCOPE(DEVICE_ID)
%
% Get assembled scope shots from the device specified by DEVICE_ID using
% the Scope Module. DEVICE_ID should be a string, e.g.,
% 'dev1000' or 'uhf-dev1000'.
%
% NOTE This example can only be ran on instruments that support API Level 5
% and higher, e.g., UHF and MF. HF2 instruments are not supported, see the
% dedicated HF2 scope example hf2_example_scope().
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
apilevel_example = 6;
% This example can't run with HF2 Instruments.
required_devtype = 'UHF|MF'; % Regular expression of supported instruments.
required_options = {}; % No special options required.
required_err_msg = ['This example is incompatible with HF2 Instruments: The ' ...
                    'HF2 Data Server does not support API Levels > 1, which ' ...
                    'is required to use the extended scope data structure. ' ...
                    'See hf2_example_scope().'];
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', required_devtype, ...
                                     'required_options', required_options, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

% Enable the API's log.
ziDAQ('setDebugLevel', 0);

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the device ready for this experiment
amplitude = 0.100;  % Signal output mixer amplitude [V].

out_channel = '0';       % signal output channel
% Get the value of the instrument's default Signal Output mixer channel.
out_mixer_channel = num2str(ziGetDefaultSigoutMixerChannel(props, str2num(out_channel)));
in_channel = '0';        % signal input channel
osc_c = '0';       % oscillator
scope_in_channel = '0';    % scope input channel
if strfind(props.devicetype, 'UHF')
    frequency = 10.0e6;
else
    frequency = 400e3;
end

% Generate the output signal.
ziDAQ('setInt', ['/' device '/sigouts/' out_channel '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_channel '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_channel '/amplitudes/' out_mixer_channel], amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_channel '/enables/' out_mixer_channel], 1);
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], frequency); % [Hz]

branches = ziDAQ('listNodes', ['/' device ], 0);
if any(strcmpi([branches], 'DEMODS'))
  % NOTE we don't need any demodulator data for this example, here we
  % configure the frequency of the output signal on out_mixer_channel (Lock-in only).
  ziDAQ('setInt', ['/' device '/demods/' out_mixer_channel '/oscselect'], str2double(osc_c));
elseif any(strcmpi([branches], 'EXTREFS'))
  % For AWG without any lock-in functionality.
  ziDAQ('setInt', ['/' device '/extrefs/' out_channel '/adcselect'], str2double(in_channel));
end

% Configure the signal inputs
ziDAQ('setInt', ['/' device '/sigins/' in_channel '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_channel '/ac'], 0);
% Perform a global synchronisation between the device and the data server:
% Ensure that the signal input and output configuration has taken effect before
% calculating the signal input autorange.
ziDAQ('sync');


% Perform an automatic adjustment of the signal inputs range based on
% the measured input signal's amplitude measured over approximately
% 100 ms. This is important to obtain the best bit resolution on the
% signal inputs of the measured signal in the scope.
ziSiginAutorange(device, in_channel);

% Configure the scope via the /device/scopes/0 branch
% 'length' : the length of each segment
ziDAQ('setInt', ['/' device '/scopes/0/length'],  int64(32e3));
% 'channel' : select the scope channel(s) to enable.
%  Bit-encoded as following:
%   1 - enable scope channel 0
%   2 - enable scope channel 1
%   3 - enable both scope channels (requires DIG option)
% NOTE we are only interested in one scope channel: scope_in_channel and leave the
% other channel unconfigured
ziDAQ('setInt',    ['/' device '/scopes/0/channel'], bitshift(1, str2double(in_channel)));
% 'channels/0/bwlimit' : bandwidth limit the scope data. Enabling bandwidth
% limiting avoids antialiasing effects due to subsampling when the scope
% sample rate is less than the input channel's sample rate.
%  Bool:
%   0 - do not bandwidth limit
%   1 - bandwidth limit
ziDAQ('setInt',    ['/' device '/scopes/0/channels/' scope_in_channel '/bwlimit'], 1);
% 'channels/0/inputselect' : the input channel for the scope:
%   0 - signal input 1
%   1 - signal input 2
%   2, 3 - trigger 1, 2 (front)
%   8-9 - auxiliary inputs 1-2
%   The following inputs are additionally available with the DIG option:
%   10-11 - oscillator phase from demodulator 3-7
%   16-23 - demodulator 0-7 x value
%   32-39 - demodulator 0-7 y value
%   48-55 - demodulator 0-7 R value
%   64-71 - demodulator 0-7 Phi value
%   80-83 - pid 0-3 out value
%   96-97 - boxcar 0-1
%   112-113 - cartesian arithmetic unit 0-1
%   128-129 - polar arithmetic unit 0-1
%   144-147 - pid 0-3 shift value
ziDAQ('setInt',    ['/' device '/scopes/0/channels/' scope_in_channel '/inputselect'], str2double(in_channel));
% 'channels/0/limitlower' and 'channels/0/limitupper' : Specify lower and upper
% limits of the scope's input value. When 'channels/0/inputselect' is a
% non-hardware channel (DIG Option), the user can specify an appropriate range
% in which to record the data from the channel in order to obtain the highest
% accuracy. These nodes are only writable if the DIG Option is enabled.
% ziDAQ('setDouble', ['/' device '/scopes/0/channels/' scope_in_channel '/limitlower'], 0.30);
% ziDAQ('setDouble', ['/' device '/scopes/0/channels/' scope_in_channel '/limitupper'], 0.40);
% 'time' : timescale of the wave, sets the sampling rate to 1.8GHz/2**time.
%   0 - sets the sampling rate to 1.8 GHz
%   1 - sets the sampling rate to 900 MHz
%   ...
%   5 - sets the sampling rate to 56.2 MHz
%   ...
%   16 - sets the samptling rate to 27.5 kHz
scope_time = 0;
ziDAQ('setInt',  ['/' device '/scopes/0/time'], scope_time);
% 'single' : only get a single scope record.
%   0 - take continuous records
%   1 - take a single records
ziDAQ('setInt',    ['/' device '/scopes/0/single'], 0);
% 'trigenable' : enable the scope's trigger (boolean).
%   0 - acquire continuous records
%   1 - only acquire a record when a trigger arrives
ziDAQ('setInt',    ['/' device '/scopes/0/trigenable'], 0);
% 'trigholdoff' : the scope hold off time inbetween acquiring triggers (still
% relevant if triggering is disabled).
ziDAQ('setDouble', ['/' device '/scopes/0/trigholdoff'], 0.05);
% 'segments/enable' : Disable segmented data recording.

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

% Subscribe to the scope's data in the module.
wave_nodepath = ['/' device '/scopes/0/wave'];
ziDAQ('subscribe', scopeModule, wave_nodepath);

min_num_records = 20;
fprintf('Obtaining scope data with triggering disabled...\n')
data_no_trig = getScopeRecords(device, scopeModule, min_num_records);
if ziCheckPathInData(data_no_trig, wave_nodepath)
  checkScopeRecordFlags(data_no_trig.(device).scopes(1).wave);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Configure the scope and obtain data with triggering enabled.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 'trigenable' : enable the scope's trigger (boolean).
ziDAQ('setInt',    ['/' device '/scopes/0/trigenable'], 1);
% Specify the trigger channel, we choose the same as the scope input
ziDAQ('setInt',    ['/' device '/scopes/0/trigchannel'], str2double(in_channel));
% Trigger on rising edge?
ziDAQ('setInt',    ['/' device '/scopes/0/trigrising'], 1);
% Trigger on falling edge?
ziDAQ('setInt',    ['/' device '/scopes/0/trigfalling'], 0);
% Set the trigger threshold level
ziDAQ('setDouble', ['/' device '/scopes/0/triglevel'], 0.00);
% Set hysteresis triggering threshold to avoid triggering on noise
% 'trighysteresis/mode' :
%  0 - absolute, use an absolute value ('trighysteresis/absolute')
%  1 - relative, use a relative value (trighysteresis/relative') of the trigchannel's input range
ziDAQ('setDouble',    ['/' device '/scopes/0/trighysteresis/mode'], 1);
ziDAQ('setDouble',    ['/' device '/scopes/0/trighysteresis/relative'], 0.1); % 0.1=10%

% Set the trigger hold-off mode of the scope. After recording a trigger event,
% this specifies when the scope should become re-armed and ready to trigger,
% 'trigholdoffmode':
% 0 - specify a hold-off time between triggers in seconds ('scopes/0/trigholdoff'),
% 1 - specify a number of trigger events before re-arming the scope ready to trigger ('scopes/0/trigholdcount').
ziDAQ('setInt', ['/' device '/scopes/0/trigholdoffmode'], 0);
ziDAQ('setDouble',    ['/' device '/scopes/0/trigholdoff'], 0.050);
% The trigger reference position relative within the wave, a value of
% 0.5 corresponds to the center of the wave.
ziDAQ('setDouble', ['/' device '/scopes/0/trigreference'], 0.25);
% Set trigdelay to 0.: Start recording from when the trigger is activated.
ziDAQ('setDouble',    ['/' device '/scopes/0/trigdelay'], 0.0);
% Disable trigger gating.
ziDAQ('setInt', ['/' device '/scopes/0/triggate/enable'], 0);

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
%% Configure the Scope Module to calulate the FFT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Set the Scope Module's mode to return frequency domain data.
ziDAQ('set', scopeModule, 'mode', 3);
% Use a Hann window function.
ziDAQ('set', scopeModule, 'fft/window', 1);

% Enable the scope and read the scope data arriving from the device; the Scope
% Module will additionally perform an FFT on the data. Note: The other module
% parameters are already configured and the required data is already subscribed
% from above.
fprintf('Obtaining FFT''d scope data with triggering disabled...\n')
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
  plotScopeRecords(records_no_trig, str2num(scope_in_channel), scope_time, clockbase);
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
  plotScopeRecords(records_trig, str2num(scope_in_channel), scope_time, clockbase);
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
  plotScopeRecords(records_fft, str2num(scope_in_channel), scope_time, clockbase);
end
title('\bf FFT of Scope records (triggering enabled)');
grid on;
box on;
xlabel('Frequency (MHz)');
fprintf('Number of scope records with triggering disabled (and FFT''d): %d.\n', num_records_fft);

end

function data = getScopeRecords(device, scopeModule, num_records)
% GETSCOPERECORDS  Obtain scope records from device using an Scope Module.

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

function plotScopeRecords(scope_records, scope_in_channel, scope_time, clockbase)
% plotScopeRecords Plot the scope records.
  num_records = length(scope_records);
  c = hsv(num_records);
  for ii=1:num_records
    totalsamples = double(scope_records{ii}.totalsamples);
    if ~bitand(scope_records{ii}.channelmath(scope_in_channel+1), 2)
      dt = scope_records{ii}.dt;
      % The timestamp is the last timestamp of the last sample in the scope segment.
      timestamp = double(scope_records{ii}.timestamp);
      triggertimestamp = double(scope_records{ii}.triggertimestamp);
      t = linspace(-totalsamples, 0, totalsamples)*dt + (timestamp - ...
                                                        triggertimestamp)/double(clockbase);
      plot(1e6*t, scope_records{ii}.wave(:, scope_in_channel+1), 'color', c(ii, :));
      hold on;
      plot([0.0, 0.0], get(gca, 'ylim'), '--k');
    elseif bitand(scope_records{ii}.channelmath(scope_in_channel+1), 2)
      scope_rate = double(clockbase)/2^scope_time;
      f = linspace(0, scope_rate/2, totalsamples);
      semilogy(f/1e6, scope_records{ii}.wave(:, scope_in_channel+1), 'color', c(ii, :));
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
