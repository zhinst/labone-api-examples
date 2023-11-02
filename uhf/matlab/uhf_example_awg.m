function data = uhf_example_awg(device_id)
% UHF_EXAMPLE_AWG_SOURCEFILE demonstrates how to connect to a
% Zurich Instruments Arbitrary Waveform Generator and compile/upload
% an AWG program to the instrument.
%
% USAGE DATA = UHF_EXAMPLE_AWG_SOURCEFILE(DEVICE_ID)
%
% DEVICE_ID should be a string, e.g., 'dev1000' or 'uhf-dev1000'.
% DATA contains the measured scope shot of AWG signal.
%
% NOTE This example can only be ran on UHF instruments with the AWG option
% enabled or on UHFAWG instruments.
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
if ~(exist('ziDAQ', 'file') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end

% The API level supported by this example.
apilevel_example = 6;
% Create an API session; connect to the correct Data Server for the device.
required_err_msg = ['This example can only be ran on either a UHFAWG or' ...
                    'a UHF with the AWG option enabled.'];
[device, props] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'UHF', ...
                                     'required_err_msg', required_err_msg);
if (strcmpi('UHFLI', props.devicetype) == 1) &&...
        ~any(cellfun(@(x) ~isempty(x), strfind(props.options,'AWG')))
    error(['Required option set not satisfied. This example only ' ...
           'runs on UHFLI with the AWG Option installed.'],device)
end
ziApiServerVersionCheck();

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%% channel selction %%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Output channel
out_c = '0';
% Input channel
in_c = '0';
% AWG channel
awg_c = '0';
% amplitude [V]
amplitude = 1.0;
% Output full scale
full_scale = 0.75;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Settings %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Input
% AC/DC coupling
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 0);
% input impedance 50 ohm
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
% Single-ended input
ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
% Input range
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 1.0);
%%% Output
% Turn on the output
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
% Output range 1.5 V
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1.5);
%%% AWG
% AWG sampling rate at 1.8 GSa/s
ziDAQ('setInt', ['/' device '/awgs/0/time'], 0);
% AWG amplitude range
ziDAQ('setDouble', ['/' device '/awgs/0/outputs/' awg_c '/amplitude'], amplitude);
% AWG in its plain mode
ziDAQ('setInt', ['/' device '/awgs/0/outputs/' awg_c '/mode'], 0);
% AWG registers at 0
ziDAQ('setDouble', ['/' device '/awgs/0/userregs/*'], 0);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% AWG %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Number of points in AWG waveform
AWG_N = 2000;

% Define an AWG program as a string stored in the variable awg_program,
% equivalent to what would be entered in the Sequence Editor window in the graphical UI.
% This example demonstrates four methods of definig waveforms via the API
% - (wave w0) loaded directly from programmatically generated CSV file wave0.csv.
%             Waveform shape: Blackman window with negative amplitude.
% - (wave w1) using the waveform generation functionalities available in the AWG Sequencer language.
%             Waveform shape: Gaussian function with positive amplitude.
% - (wave w2) using the vect() function and programmatic string replacement.
%             Waveform shape: Single period of a sine wave.
% - (wave w3) directly writing an array of numbers to the AWG waveform memory.
%             Waveform shape: Sinc function. In the sequencer language, the waveform is initially
%             defined as an array of zeros. This placeholder array is later overwritten with the
%             sinc function.

% AWG program
awg_program_lines = {...
     'const AWG_N = _c1_;',...
     'wave w0 = "wave0";',...
     'wave w1 = gauss(AWG_N, AWG_N/2, AWG_N/20);',...
     'wave w2 = vect(_w2_);',...
     'wave w3 = zeros(AWG_N);',...
     'while(getUserReg(0) == 0);',...
     'setTrigger(1);',...
     'setTrigger(0);',...
     'playWave(w0);',...
     'playWave(w1);',...
     'playWave(w2);',...
     'playWave(w3);'};
awg_program = sprintf('%s\n',awg_program_lines{:});

% Define an array of values that are used to write values for wave w0 to a CSV file in the module's data directory
% The blackman function is available in the Signal Processing Toolbox.
% waveform_0 = -blackman(AWG_N)';
waveform_0 = -(0.42 - 0.5*cos(2*pi*(0:AWG_N-1)/(AWG_N-1)) + 0.08*cos(4*pi*(0:AWG_N-1)/(AWG_N-1)));

% Redefine the wave w1 in Python for later use in the plot
width = AWG_N/20;
waveform_1 = exp(-(linspace(-AWG_N/2, AWG_N/2, AWG_N).^2)./(2*width^2));

% Define an array of values that are used to generate wave w2
waveform_2 = sin(linspace(0, 2*pi, 96));

% Fill the waveform values into the predefined program by inserting the array as comma-separated
% floating-point numbers into awg_program.
% Warning: Defining waveforms with the vect function can increase the code size
%          considerably and should be used for short waveforms only.
str = num2str(waveform_2(1),'%1.10f');
for nn = 2:length(waveform_2)
    str = sprintf([str ',%1.10f'],waveform_2(nn));
end
awg_program = strrep(awg_program, '_w2_', str);

% Do the same with the integer constant AWG_N
awg_program = strrep(awg_program, '_c1_', num2str(AWG_N));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
% Create an instance of the AWG Module
h = ziDAQ('awgModule');
ziDAQ('set', h, 'device', device);
ziDAQ('execute', h);

% Get the modules data directory
data_dir = ziDAQ('getString', h, 'directory');

% All CSV files within the waves directory are automatically recognized by the AWG module
wave_dir = [data_dir filesep fullfile('awg', 'waves')];
if ~(exist(wave_dir,'dir') == 7)
    % The data directory is created by the AWG module and should always exist.
    % If this exception is raised, something might be wrong with the file system.
    error('AWG module wave directory %s does not exist or is not a directory', wave_dir);
end
% Save waveform data to CSV
fid = fopen([wave_dir filesep 'wave0.csv'],'wt');
fprintf(fid,'%2.18E \n', waveform_0);
fclose(fid);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Transfer the AWG sequence program. Compilation starts automatically.
ziDAQ('set', h, 'compiler/sourcestring', awg_program);
% Note: when using an AWG program from a source file (and only then), the compiler needs to
% be started explicitly with awgModule.set('compiler/start', 1)
timeout = 10;
time_start = tic;
while ziDAQ('getInt', h, 'compiler/status') == -1
    pause(0.1);
    if toc(time_start) > timeout
        error('Compiler failed to finish after %f s.', timeout);
    end
end

% Check the statuse of compilation
compilerStatus = ziDAQ('getInt', h, 'compiler/status');
compilerString = ziDAQ('getString', h, 'compiler/statusstring');
if compilerStatus == 1
    % Compilation failed, send an error message
    error(char(compilerString));
else
    if compilerStatus == 0
        disp('Compilation successful with no warnings, will upload the program to the instrument.');
    end
    if compilerStatus == 2
        disp('Compilation successful with warnings, will upload the program to the instrument.');
        disp(['Compiler warning: ' char(compilerString)]);
    end
    % Wait for waveform upload to finish
    timeout = 10;
    while ziDAQ('getDouble', h, 'progress') < 1
        pause(0.1);
        fprintf('Uploading waveform, progress: %.1f%%.\n', 100*ziDAQ('getDouble', h, 'progress'));
        if toc(time_start) > timeout
            error('Failed to upload waveform after %f s.', timeout);
        end
    end
    fprintf('Upload to the instrument successful.\n');
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Replace the waveform w3 with a new one.
% The sinc function is available in the Signal Processing Toolbox.
% waveform_3 = sinc();
% Calculate the sinc function:
x = linspace(-6*pi, 6*pi, AWG_N);
waveform_3 = (sin(pi*x))./(pi*x);
waveform_3(x==0) = 1;
% Let N be the total number of waveforms and M>0 be the number of waveforms defined from CSV file. Then the index of
% the waveform to be replaced is defined as following:
% - 0,...,M-1 for all waveforms defined from CSV file alphabetically ordered by filename,
% - M,...,N-1 in the order that the waveforms are defined in the sequencer program.
% For the case of M=0, the index is defined as:
% - 0,...,N-1 in the order that the waveforms are defined in the sequencer program.
% Of course, for the trivial case of 1 waveform, use index=0 to replace it.
%
% The list of waves given in the Waveform sub-tab of the AWG Sequencer tab can be used to help verify the AWG core and
% the index of the waveform to be replaced.
index = 3;
waveform_3_int16 = typecast(int16((pow2(15) - 1)*waveform_3), 'int16');
ziDAQ('setVector',['/' device '/awgs/0/waveform/waves/' num2str(index)], waveform_3_int16);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Configure the Scope for measurement

% Disable the scope.
ziDAQ('setInt', ['/' device '/scopes/0/enable'], 0);
% Enable channel 1 of the scope: 1: channel 1; 2: channel 2; 3: both channels.
ziDAQ('setInt', ['/' device '/scopes/0/channel'], 1);
% 'channels/0/inputselect' : the input channel for the scope: 0 - signal input 1
ziDAQ('setInt', ['/' device '/scopes/0/channels/0/inputselect'], str2double(in_c));
% 'time' : timescale of the wave, sets the sampling rate to 1.8GHz/2*time.
% 0 - sets the sampling rate to 1.8 GHz
% 1 - sets the sampling rate to 900 MHz
% ...
% 16 - sets the sampling rate to 27.5 kHz
freqSamp = 1.8e9;
ziDAQ('setInt', ['/' device '/scopes/0/time'], 0);
% Configure the length of the scope shot depending on the number of points
ziDAQ('setDouble', ['/' device '/scopes/0/length'], 8000);
% Now configure the scope's trigger to get aligned data
% 'trigenable' : enable the scope's trigger (boolean).
ziDAQ('setInt', ['/' device '/scopes/0/trigenable'], 1);
% Specify the trigger channel:
%
% Here we trigger on the signal from UHF signal input 1. If the instrument has the DIG Option installed we could trigger
% the scope using an AWG Trigger instead (see the `setTrigger(1);` line in `awg_program` above).
%
% 0:   Signal Input 1
% 192: AWG Trigger 1
trigchannel = 0;
ziDAQ('setInt', ['/' device '/scopes/0/trigchannel'], trigchannel);
if trigchannel == 0
    % Trigger on the falling edge of the negative blackman waveform `w0` from our AWG program.
    ziDAQ('setInt', ['/' device '/scopes/0/trigslope'], 2);  % 2 ^= falling edge.
    ziDAQ('setDouble', ['/' device '/scopes/0/triglevel'], -0.600);
    % Set hysteresis triggering threshold to avoid triggering on noise
    % 'trighysteresis/mode' :
    % 0 - absolute, use an absolute value ('scopes/0/trighysteresis/absolute')
    % 1 - relative, use a relative value ('scopes/0trighysteresis/relative') of the trigchannel's input range
    %     (0.1 = 10%).
    ziDAQ('setInt', ['/' device '/scopes/0/trighysteresis/mode'], 0);
    ziDAQ('setDouble', ['/' device '/scopes/0/trighysteresis/relative'], 0.025);
    % Set a negative trigdelay to capture the beginning of the waveform.
    trigdelay = -1.0e-6;
    ziDAQ('setDouble', ['/' device '/scopes/0/trigdelay'], trigdelay);
else
    % Assume we're using an AWG Trigger, then the scope configuration is simple: Trigger on rising edge.
    ziDAQ('setInt', ['/' device '/scopes/0/trigslope'], 1);
    % Set trigdelay to 0.0: Start recording from when the trigger is activated.
    trigdelay = 0.0;
    ziDAQ('setDouble', ['/' device '/scopes/0/trigdelay'], trigdelay);
end
% The trigger reference position relative within the wave, a value of 0.5 corresponds to the center of the wave.
trigreference = 0.0;
ziDAQ('setDouble', ['/' device '/scopes/0/trigreference'], trigreference);
% Set the hold off time in-between triggers.
ziDAQ('setDouble', ['/' device '/scopes/0/trigholdoff'], 0.025);

% Start the AWG in single-shot mode
ziDAQ('setInt', ['/' device '/awgs/0/single'], 1);
ziDAQ('setInt', ['/' device '/awgs/0/enable'], 1);

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device.
ziDAQ('sync');

% Set up the Scope Module.
scopeModule = ziDAQ('scopeModule');
% Record data in time mode.
ziDAQ('set', scopeModule, 'mode', 1);
% Subscribe to the scope data in the module.
ziDAQ('subscribe', scopeModule, ['/' device '/scopes/0/wave']);

% Tell the module to be ready to acquire data; reset the module's progress to 0.0.
ziDAQ('execute', scopeModule);

% Start the scope...
% 'single' : only get a single scope shot.
% 0 - take continuous shots
% 1 - take a single shot
ziDAQ('setInt', ['/' device '/scopes/0/single'], 1);
ziDAQ('setInt', ['/' device '/scopes/0/enable'], 1);
ziDAQ('sync');
pause(1);

% Set the AWG register to 1
ziDAQ('setInt', ['/' device '/awgs/0/userregs/0'], 1);
pause(0.1);

time_start = tic;
timeout = 30;  % [s]
records = 0;
% Wait until the Scope Module has received and processed the desired number of records.
while records < 1
  pause(0.2)
  records = ziDAQ('getInt', scopeModule, 'records');
    if toc(time_start) > timeout
      % Break out of the loop if for some reason we're no longer receiving
      % scope data from the device.
      fprintf('\nScope Module did not return %d records after %f s - forcing stop.', num_records, timeout);
      break
    end
end
% Disable the scope.
ziDAQ('setInt', ['/' device '/scopes/0/enable'], 0);

% Read the data out from the module.
data = ziDAQ('read', scopeModule);

ziDAQ('finish', scopeModule);

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', scopeModule);
ziDAQ('clear', h);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Extracting measurement data
if ziCheckPathInData(data, ['/' device '/scopes/0/wave'])
    segment = data.(device).scopes(1).wave{1};
    signal_measured = segment.wave;
    time_measured = (-double(segment.totalsamples) + 1:1:0)*segment.dt + double(segment.timestamp - segment.triggertimestamp)/freqSamp;
else
  error('No scope measurement; please try again.');
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%% post processing %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Expected waveform
signal_expected = [waveform_0 waveform_1 waveform_2 waveform_3]*full_scale*amplitude;

% The shift between measured and expected signal depends among other things on cable length.
% We simply determine the shift experimentally and then plot the signals with an according correction on the horizontal axis.
N_expected = length(signal_expected);
N_measured = length(signal_measured);
% The xcorr function is available in the Signal Processing Toolbox.
% correlation = xcorr(signal_measured,signal_expected);
correlation = CrossCorrelation(signal_measured,signal_expected);
[value_max,index_max_1] = max(correlation);
index_match = max(index_max_1,2*max(N_expected,N_measured) - index_max_1) - max(N_expected,N_measured);
time_shift = index_match/freqSamp - trigreference*(time_measured(end) - time_measured(1)) + trigdelay;
time_expected = linspace(0, length(signal_expected)/freqSamp, length(signal_expected)) + time_shift;
% Plot
figure('Name','UHF-AWG','NumberTitle','on');
set(gca,'FontSize',12,...
    'LineWidth',2,...
    'Color',[1 1 1],...
    'Box','on');
title('Measured and expected AWG signal');
xlabel('Time [ \mus ]','fontsize',12,'fontweight','n','color','k');
ylabel('Amplitude  [ V ]','fontsize',12,'fontweight','n','fontangle','n','color','k');
grid on
hold on
h = plot(time_measured*1e6,signal_measured);
set(h,'LineWidth',2,'LineStyle','-','Color','b')
h = plot(time_expected*1e6,signal_expected);
set(h,'LineWidth',2,'LineStyle','-.','Color','r')
h = legend('Measurement','Model');
set(h,'Box','on','Color','w','Location','NorthWest','FontSize',12,'FontWeight','n','FontAngle','n')

% Normalized correlation coefficient.
norm_correlation_coeff = value_max/sqrt(sum(signal_expected.^2)*sum(signal_measured.^2));
if norm_correlation_coeff > 0.95
    fprintf('Measured and expected signals agree, normalized correlation coefficient: %f.\n', norm_correlation_coeff);
else
    error('Detected a disagreement between the measured and expected signals, normalized correlation coefficient: %f.\n', norm_correlation_coeff);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end

function r = CrossCorrelation(x,y)
    %%% Change to row vector
    if iscolumn(x)
        x = x';
    end
    if iscolumn(y)
        y = y';
    end
    %%% Length of correlation vector
    nCommon = max(length(x), length(y));
    r = zeros(1,2*nCommon - 1);
    %%% Zero padding
    if nCommon > length(x)
        u = [x zeros(1,nCommon - length(x))];
        v = y;
    else
        u = x;
        v = [y zeros(1,nCommon - length(y))];
    end
    %%% Computing the correlation
    for nn = 0:nCommon - 1
        r(nCommon + nn) = sum(u(nn + 1:nCommon).*v(1:nCommon - nn));
        r(nCommon - nn) = sum(u(1:nCommon - nn).*v(nn + 1:nCommon));
    end
end
