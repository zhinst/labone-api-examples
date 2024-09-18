function ziAddExamplePath
% ZIADDEXAMPLEPATH add the LabOne Matlab examples to Matlab's Search Path
%
% USAGE:
% ziAddExamplePath();

% Get the name of the current function complete with full path
mfile = which(mfilename);
[pathstr, name] = fileparts(mfile);
dirs = {'hf2-mf-uhf' 'hdawg' 'hf2' 'mf' 'uhf' 'shfli' 'ghfli'};
for dir = dirs
    driverPath = [pathstr filesep string(dir) filesep 'matlab'];
    addpath(char(strjoin(driverPath,'')))
end
dbs = dbstack;
% If ziAddExamplePath was called directly in Matlab output some help, otherwise output nothing.
if strcmp(dbs(end).name, 'ziAddExamplePath')
    fprintf('Added ziDAQ''s Examples directories to Matlab''s path\n')
    fprintf('for this session.\n\n');
    fprintf('To make this configuration persistent across Matlab sessions either:\n\n')
    fprintf('1. Run the ''pathtool'' command in the Matlab Command Window and add the\n')
    fprintf('   following paths WITH SUBFOLDERS to the Matlab search path:\n\n')
    fprintf('   %s\n', pathstr);
    fprintf('\nor\n\n');
    fprintf('2. Add the following line to your Matlab startup.m file:\n');
    fprintf('\n');
    fprintf('   run(''%s%s%s'');\n\n', pathstr, filesep, name);
    fprintf('\n');
    fprintf('See the LabOne Programming Manual for more help.\n');
end
