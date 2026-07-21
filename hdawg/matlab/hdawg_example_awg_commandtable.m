function hdawg_example_awg_commandtable(device_id)
% Demonstrate how to connect to a Zurich Instruments HDAWG and upload and run an AWG program using 
%the command table.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% USAGE 
% The example can be execute with the command:
%
% hdawg_example_awg_commandtable(device_id)
%
% device_id should be a string, e.g., 'dev1000' or 'hdawg-dev1000'.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% NOTES
%
% This example can only be ran on HDAWG instruments.
%
% Additional configuration: Connect wave outputs 1 and 2 of HDAWG to input channels 1 and 2 of an
% osciloscope with an SMA/BNC cable. The generated signals are Gaussian with opposite signs and equal
% amplitudes 
%
%
% Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in your MATLAB path. To do this
% (temporarily) for one MATLAB session please navigate to the ziDAQ base folder containing the
% 'Driver', 'Examples' and 'Utils' subfolders and run the MATLAB function ziAddPath().
% >>> ziAddPath;
%
% To obtain help on all the available ziDAQ commands, use either of the 
% commands:
% >>> help ziDAQ
% >>> doc ziDAQ

clear ziDAQ;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Check correct configuration
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Check that device_id has been correctly provided
if ~exist('device_id', 'var')
    error(['No value for device_id specified. The first argument to the ' ...
           'example should be the device ID on which to run the example, ' ...
           'e.g. ''dev1000'' or ''hdawg-dev1000''.'])
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Connect to the Data Server and to the device
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
server_host = 'localhost';
server_port = 8004;
apilevel_example = 6;
interface = '1GbE';

% Create and API session to the Data Server
ziDAQ('connect', server_host, server_port, apilevel_example)
% Establish a connection between Data Server and device
ziDAQ('connectDevice', device_id, interface)

% Create a base configuration: Disable all available outputs, awgs,...
ziDAQ('syncSetInt',['/' device_id '/system/preset/load'], 1);
% Wait for preset application to be finished
timeout = 10.0;
time_start = tic;
while(true)
    if ziDAQ('getInt',['/' device_id '/system/preset/busy']) == 0
        break
    else
        if toc(time_start) > timeout
            error('Could not finish the preset application after %f s.', timeout);
        end
        pause(0.01);
    end

end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Basic configuration
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Specify the device configuration. Firstly select the AWG core, and therefore the output channels.
% Then set the output range for each channels and output gains. Finally, activate the outputs.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
awg_c = 0;      % AWG core
range = 1.0;    % Output range [V]
ch1 = 2*awg_c;  % Output channels
ch2 = 2*awg_c+1;

awg_c_s = num2str(awg_c);   % Strings
ch1_s = num2str(ch1);
ch2_s = num2str(ch2);

% Configure the HDAWG to use one sequencer for each pair of output channels
ziDAQ('setInt', ['/', device_id '/system/awg/channelgrouping'], 0);
% Set the output gains matrix to identity
ziDAQ('setDouble', ['/' device_id '/awgs/' awg_c_s '/outputs/0/gains/0'], 1.0);
ziDAQ('setDouble', ['/' device_id '/awgs/' awg_c_s '/outputs/0/gains/1'], 0.0);
ziDAQ('setDouble', ['/' device_id '/awgs/' awg_c_s '/outputs/1/gains/0'], 0.0);
ziDAQ('setDouble', ['/' device_id '/awgs/' awg_c_s '/outputs/1/gains/1'], 1.0);
% Turn off modulation mode
ziDAQ('setInt', ['/' device_id '/awgs/' awg_c_s '/outputs/0/modulation/mode'], 0);
ziDAQ('setInt', ['/' device_id '/awgs/' awg_c_s '/outputs/1/modulation/mode'], 0);
% Set the output range
ziDAQ('setDouble', ['/' device_id '/sigouts/' ch1_s '/range'], range);
ziDAQ('setDouble', ['/' device_id '/sigouts/' ch2_s '/range'], range);
% Turn on signal output 1 and signal output 2
ziDAQ('setInt', ['/' device_id '/sigouts/' ch1_s '/on'], 1);
ziDAQ('setInt', ['/' device_id '/sigouts/' ch2_s '/on'], 1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% AWG sequencer program
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define an AWG program as a string stored in the variable `awg_program`, equivalent to what would be
% entered in the Sequence Editor window in the graphical UI. Differently to a self-contained program,
% this example refers to a command table by the instruction `executeTableEntry`, and to a placeholder
% waveforms `p1` and `p2` by the instruction `placeholder`. Both the command table and the waveform
% data for the placeholders need to be uploaded separately before this sequence program can be run.

% After defining the sequencer program, this must be compiled before being uploaded. Here the
% compilation is performed using the LabOne module awgModule.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Define the AWG program
wfm_index = 10; % Index of the slot in the waveform memory
wfm_length = 1024;
awg_program_lines = {...
     '// Define placeholder with 1024 samples',...
     sprintf('wave p1 = placeholder(%d);', wfm_length),...
     sprintf('wave p2 = placeholder(%d);', wfm_length),...
     '',...
     '// Assign an index to the placeholder waveform',...
     sprintf('assignWaveIndex(1,p1, 2,p2, %d);', wfm_index),...
     '',...
     'while(true) {',...
     '   executeTableEntry(0);',...
     '}'};
awg_program = sprintf('%s\n',awg_program_lines{:});

% Create an instance of the AWG Module
awgModule = ziDAQ('awgModule');
ziDAQ('set', awgModule, 'device', device_id);
ziDAQ('set', awgModule, 'index', awg_c);
ziDAQ('execute', awgModule);
disp('Starting compilation of the AWG sequence.');

% Transfer the AWG sequence program. Compilation starts automatically.
% Note: when using an AWG program from a source file (and only then), the compiler needs to be
% started explicitly with awgModule.set('compiler/start', 1)
ziDAQ('set', awgModule, 'compiler/sourcestring', awg_program);

% Wait until compilation is done
timeout = 10;
time_start = tic;
while ziDAQ('getInt', awgModule, 'compiler/status') == -1
    if toc(time_start) > timeout
        ziDAQ('clear', awgModule);
        error('Compiler failed to finish after %f s.', timeout);
    end
    pause(0.01);
end

% Check the status of compilation
compilerStatus = ziDAQ('getInt', awgModule, 'compiler/status');
compilerString = ziDAQ('getString', awgModule, 'compiler/statusstring');
if compilerStatus == 0
    disp('Compilation successful with no warnings, will upload the program to the instrument.');
end
if compilerStatus == 1
    ziDAQ('clear', awgModule);
    error(['Error during sequencer compilation: ' char(compilerString)])
end
if compilerStatus == 2
    disp('Compilation successful with warnings, will upload the program to the instrument.');
    disp(['Compiler warning: ' char(compilerString)]);
end

% Wait for sequence upload to finish
timeout = 10;
time_start = tic;
while ziDAQ('getInt', ['/' device_id '/awgs/' awg_c_s '/ready']) == 0
    if toc(time_start) > timeout
        ziDAQ('clear', awgModule);
        error('Failed to upload sequence after %.1f s.', timeout);
    end
    pause(0.01);
end
disp('Sequence successfully uploaded.')

% Release AWG module resources.
ziDAQ('clear', awgModule);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Command Table definition and upload
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The waveforms are played by a command table, whose structure must conform to a defined schema. The
% schema can be read at https://docs.zhinst.com/hdawg/commandtable/v1_1/schema
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Create the command table
ct = struct();
ct.header.version = '1.1.0';    % version specification is mandatory
ct.table{1}.index = 0;
ct.table{1}.waveform.index = wfm_index;
ct.table{1}.amplitude0.value = 1.0;
ct.table{1}.amplitude1.value = 1.0;
ct_json_str = jsonencode(ct); % Encode the command table into a JSON string

% Upload the command table and wait until the upload has finished
disp('Uploading the command table.');
ziDAQ('setVector', ['/' device_id '/awgs/' awg_c_s '/commandtable/data'], ct_json_str);

timeout = 10;
start_time = tic;
while(true)
    ct_status = ziDAQ('getInt', ['/' device_id '/awgs/' awg_c_s '/commandtable/status']);
    if ct_status == 1
        % Upload successful
        break
    elseif ct_status == 8
        % Error in command table
        error('The upload of the command table failed.')
    end
    if toc(start_time) > timeout
        % Timeout
        error('Command table not uploaded within %.1f s.', timeout)
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Waveform upload
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Replace the placeholder waveform with with a drag pulse (I quadrature is a gaussian and Q 
% quadrature is the derivative of I). The waveform data is uploaded to the index `wfm_index`, which 
% must be the same specified by the `assignWaveIndex` sequencer instruction.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Define the waveform
x = linspace(-round(wfm_length/2), round(wfm_length/2), wfm_length);
sigma = round(wfm_length/8);
waveform1 = exp(x.^2 ./ (2*sigma^2));
waveform2 = -x / sigma^2 .* waveform1;

% Convert to the native AWG waveform format
waveform1_int16 = typecast(int16((pow2(15) - 1)*waveform1), 'int16');
waveform2_int16 = typecast(int16((pow2(15) - 1)*waveform2), 'int16');
waveform_native = reshape([waveform1_int16; waveform2_int16], 1,[]);

% Upload the waveform to the device
ziDAQ('setVector',['/' device_id '/awgs/' awg_c_s '/waveform/waves/' num2str(wfm_index)], waveform_native);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Enable the AWG
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
disp('Enabling the AWG.');
ziDAQ('setInt', ['/' device_id '/awgs/' awg_c_s '/single'], 1);
ziDAQ('syncSetInt', ['/' device_id '/awgs/' awg_c_s '/enable'], 1);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
disp('Example ended successfully!')
end
