function hdawg_example_awg(device_id)
% HDAWG_EXAMPLE_AWG_SOURCEFILE demonstrates how to connect to a
% Zurich Instruments Arbitrary Waveform Generator and compile/upload
% an AWG program to the instrument.
%
% USAGE HDAWG_EXAMPLE_AWG(DEVICE_ID)
%
% DEVICE_ID should be a string, e.g., 'dev8006' or 'hdawg-dev8006'.
%
% NOTE This example can only be ran on HDAWG instruments with the AWG option
% enabled or on HDAWG instruments.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% of an osciloscope with an SMA/BNC cable.
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
           'e.g. ''dev2006'' or ''uhf-dev2006''.'])
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
required_err_msg = 'This example can only be ran on an HDAWG.';
[device, ~] = ziCreateAPISession(device_id, apilevel_example, ...
                                     'required_devtype', 'HDAWG', ...
                                     'required_err_msg', required_err_msg);
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
% Output mixer channel
% out_mixer_c = '3';
% AWG channel
awg_c = '0';
% amplitude [V]
amplitude = 1.0;
% Output full scale
% full_scale = 0.75;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Settings %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Output
% Turn on the first output
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
% Output range 1.5 V
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1.0);
%%% AWG
% 'system/awg/channelgrouping' : Configure how many independent sequencers
%   should run on the AWG and how the outputs are grouped by sequencer.
%   0 : 4x2 with HDAWG8; 2x2 with HDAWG4.
%   1 : 2x4 with HDAWG8; 1x4 with HDAWG4.
%   2 : 1x8 with HDAWG8.
% Configure the HDAWG to use one sequencer for each pair of output channels
ziDAQ('setInt', ['/', device '/system/awg/channelgrouping'], 0);
% AWG sampling rate at 1.8 GSa/s
ziDAQ('setInt', ['/' device '/awgs/0/time'], 0);
% AWG amplitude range
ziDAQ('setDouble', ['/' device '/awgs/0/outputs/' awg_c '/amplitude'], amplitude);
% AWG in its plain mode
ziDAQ('setInt', ['/' device '/awgs/0/outputs/' awg_c '/modulation/mode'], 0);
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
waveform_0 = -(0.42 - 0.5*cos(2*pi*(0:AWG_N-1)/(AWG_N-1)) + 0.08*cos(4*pi*(0:AWG_N-1)/(AWG_N-1)));

% Redefine the wave w1 in MATLAB for later use in the plot
width = AWG_N/20;
waveform_1 = exp(-(linspace(-AWG_N/2, AWG_N/2, AWG_N).^2)./(2*width^2));

% Define an array of values that are used to generate wave w2
waveform_2 = sin(linspace(0, 2*pi, 96));

% Fill the waveform values into the predefined program by inserting
% the array as comma-separated floating-point numbers into awg_program.
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
    ziDAQ('clear', h);
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
timeout = 5;
time_start = tic;
while ziDAQ('getInt', h, 'compiler/status') == -1
    pause(0.1);
    if toc(time_start) > timeout
        ziDAQ('clear', h);
        error('Compiler failed to finish after %f s.', timeout);
    end
end

% Check the statuse of compilation
compilerStatus = ziDAQ('getInt', h, 'compiler/status');
compilerString = ziDAQ('getString', h, 'compiler/statusstring');
if compilerStatus == 1
    % Compilation failed, send an error message
    ziDAQ('clear', h);
    error(char(compilerString))
else
    if compilerStatus == 0
        disp('Compilation successful with no warnings, will upload the program to the instrument.');
    end
    if compilerStatus == 2
        disp('Compilation successful with warnings, will upload the program to the instrument.');
        disp(['Compiler warning: ' char(compilerString)]);
    end
    % Wait for waveform upload to finish
    timeout = 5;
    while ziDAQ('getDouble', h, 'progress') < 1
        pause(0.1);
        fprintf('Uploading waveform, progress: %.1f%%.\n', 100*ziDAQ('getDouble', h, 'progress'));
        if toc(time_start) > timeout
            ziDAQ('clear', h);
            error('Failed to upload waveform after %f s.', timeout);
        end
    end
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
% The set command below on awgs/0/waveform/index defines the index of the waveform in the sequencer program to
% replace with the data that is written to awgs/0/waveform/data.
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
% Start the AWG in single-shot mode.
% Preferred method of using the AWG: Run in single mode, continuous waveform playback is best achieved by using an
% infinite loop (e.g., while (true)) in the sequencer program.
disp(['Enabling the AWG: Set /', device, '/awgs/0/userregs/0 to 1 to trigger playback.']);
ziDAQ('setInt', ['/' device '/awgs/0/single'], 1);
ziDAQ('setInt', ['/' device '/awgs/0/enable'], 1);

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Expected waveform
signal_expected = [waveform_0 waveform_1 waveform_2 waveform_3]*amplitude;
freqSamp = 2.4E9;
time_expected = linspace(0, length(signal_expected)/freqSamp, length(signal_expected));
% Plot
figure('Name','HDAWG','NumberTitle','on');
set(gca,'FontSize',12,'LineWidth',2,'Color',[1 1 1],'Box','on');
h = plot(time_expected*1e6,signal_expected);
set(h,'LineWidth',1.5,'LineStyle','-','Color','r')
title('Expected AWG Signal');
xlabel('Time (\mus)','fontsize',12,'fontweight','n','color','k');
ylabel('Amplitude  (V)','fontsize',12,'fontweight','n','fontangle','n','color','k');
grid on
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end
