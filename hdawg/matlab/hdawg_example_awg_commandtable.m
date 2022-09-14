function hdawg_example_awg_commandtable(device_id)
% HDAWG_EXAMPLE_AWG_COMMANDTABLE demonstrates how to connect and use to a 
% Zurich Instruments HDAWG and upload and run an AWG program using the 
% Command Table feature.
%
% USAGE HDAWG_EXAMPLE_AWG_COMMANDTABLE(DEVICE_ID)
%
% DEVICE_ID should be a string, e.g., 'dev8006' or 'hdawg-dev8006'.
%
% NOTE This example can only be ran on HDAWG instruments.
%
% NOTE Additional configuration: Connect wave outputs 1 and 2 of HDAWG 
% to input channels 1 and 2 of an osciloscope with an SMA/BNC cable. The
% generated signals are Gaussian with opposite signs and equal amplitusdes 
%
%
% NOTE Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in 
% your MATLAB path. To do this (temporarily) for one MATLAB session please 
% navigate to the ziDAQ base folder containing the 'Driver', 'Examples' 
% and 'Utils' subfolders and run the MATLAB function ziAddPath().
% >>> ziAddPath;
%
% Use either of the commands:
% >>> help ziDAQ
% >>> doc ziDAQ
% in the MATLAB command window to obtain help on all available ziDAQ commands.
% Copyright 2008-2021 Zurich Instruments AG

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

% Create a base configuration: Disable all available outputs, awgs,...
ziDisableEverything(device);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Device settings 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 'system/awg/channelgrouping' : Configure how many independent sequencers
%   should run on the AWG and how the outputs are grouped by sequencer.
%   0 : 4x2 with HDAWG8; 2x2 with HDAWG4.
%   1 : 2x4 with HDAWG8; 1x4 with HDAWG4.
%   2 : 1x8 with HDAWG8.
% Configure the HDAWG to use one sequencer for each pair of output channels
ziDAQ('setInt', ['/', device '/system/awg/channelgrouping'], 0);

% Turn on signal output 1 and signal output 2
ziDAQ('setInt', ['/' device '/sigouts/0/on'], 1);
ziDAQ('setInt', ['/' device '/sigouts/1/on'], 1);

% Set the output range to 1 V
ziDAQ('setDouble', ['/' device '/sigouts/0/range'], 1.0);
ziDAQ('setDouble', ['/' device '/sigouts/1/range'], 1.0);

% Set the output amplitude to 1 V
amplitude = 1.0;
ziDAQ('setDouble', ['/' device '/awgs/0/outputs/0/gains/0'], amplitude);
ziDAQ('setDouble', ['/' device '/awgs/0/outputs/1/gains/1'], amplitude);

% Turn off modulation mode
ziDAQ('setInt', ['/' device '/awgs/0/outputs/0/modulation/mode'], 0);
ziDAQ('setInt', ['/' device '/awgs/0/outputs/1/modulation/mode'], 0);

% Clear the command table
ziDAQ('setInt', ['/' device '/awgs/0/commandtable/clear'], 1);

% Ensure the device configuration has taken effect.
ziDAQ('sync');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% AWG sequence
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% AWG SeqC program
awg_program_lines = {...
     '// Define placeholder with 1024 samples',...
     'wave p = placeholder(1024);',...
     '',...
     '// Assign placeholder to waveform index 10',...
     'assignWaveIndex(p, p, 10);',...
     '',...
     'while(true) {',...
     '   executeTableEntry(0);',...
     '}'};
awg_program = sprintf('%s\n',awg_program_lines{:});

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Command Table JSON content
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% Read the command table from a JSON file if available. 
% json_file = 'command_table.json';
% json_str = fileread(json_file);

%%% Provide JSON string directly if there is no JSON file available
json_str_lines = {...
    '{',...
    '"header": {',...
    '"version": "1.0.0",',...
    '},',...
    '"table": [',...
    '{',...
    '"index": 0,',...
    '"waveform": {',...
    '"index": 10',...
    '},',...
    '"amplitude0": {',...
    '"value": 1.0',...
    '},',...
    '"amplitude1": {',...
    '"value": 1.0',...
    '}',...
    '}',...
    ']',...
    '}'};
json_str = sprintf('%s\n', json_str_lines{:});

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compile and upload
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Create an instance of the AWG Module
h = ziDAQ('awgModule');
ziDAQ('set', h, 'device', device);
ziDAQ('execute', h);

% Transfer the AWG sequence program. Compilation starts automatically.
ziDAQ('set', h, 'compiler/sourcestring', awg_program);
% Note: when using an AWG program from a source file (and only then), the compiler needs to
% be started explicitly with awgModule.set('compiler/start', 1)
timeout = 10;
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
    timeout = 10;
    while ziDAQ('getDouble', h, 'progress') < 1
        pause(0.1);
        fprintf('Uploading waveform, progress: %.1f%%.\n', 100*ziDAQ('getDouble', h, 'progress'));
        if toc(time_start) > timeout
            ziDAQ('clear', h);
            error('Failed to upload waveform after %f s.', timeout);
        end
    end
end

% Release AWG module resources.
ziDAQ('clear', h);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Upload the Command Table 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ziDAQ('setVector', ['/' device '/awgs/0/commandtable/data'], json_str);
ct_status = ziDAQ('getInt', ['/' device '/awgs/0/commandtable/status']);
if ct_status ~= 1
    % Command table upload failed
    error('Command table upload failed.')

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Replace the placeholder with a waveform
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Define a Gaussian waveform 
x = 0:1:1023;
sigma = 150;
w = exp(-0.5*((x - 512)/sigma).^2);

% Upload waveform data with the index 10 (this is the index assigned with 
% the assignWaveIndex sequencer instruction
index = 10;
w_int16 = typecast(int16((pow2(15) - 1)*w), 'int16');
waveform = [w_int16; -w_int16];
ziDAQ('setVector',['/' device '/awgs/0/waveform/waves/' num2str(index)], waveform);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Enable the AWG sequencer
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fprintf('Enabling the AWG.\n');
ziDAQ('setInt', ['/' device '/awgs/0/single'], 1);
ziDAQ('setInt', ['/' device '/awgs/0/enable'], 1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end