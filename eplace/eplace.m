function varargout = eplace(varargin)
% Electrode placement GUI for post-operative CT images
% 
% Usage
%   eplace; % GUI
% 
%   elec = eplace( 'gui_mode', 'interactive');
%   elec = eplace( 'mri', full-path-to-ct_image, 'label', label-text-file);
% 
%   % To implement
%   elec = eplace( 'mri', full-path-to-ct_image, 'label', label-text-file, 'maskdir', full-path-to-auto-masks);
% 
% Output
%   data structure with following fields
%          rois, Nx1 cell array of image index for each electrode
%        labels, Nx1 string cell array of electrode labels
%         coord, different kinds of coordinates of each electrode
%       elecpos, a subset of coord
%          mask, not used yet
%           reg, reserved to save transformation matrix 
%          proj, reserved to save projected electrodes
%         atlas, reserved to save atlas query results
% 
% Tested on Matlab R2018b, macOS Mojave.
% 
% naturalzhou@gmail.com
% Zelano Lab @ Northwestern University
% https://sites.northwestern.edu/zelano/
% 
%     This program is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
% 
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
% 
%     You should have received a copy of the GNU General Public License
%     along with this program.  If not, see <https://www.gnu.org/licenses/>.

% 
% EPLACE MATLAB code for eplace.fig
%      EPLACE, by itself, creates a new EPLACE or raises the existing
%      singleton*.
%
%      H = EPLACE returns the handle to a new EPLACE or the handle to
%      the existing singleton*.
%
%      EPLACE('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in EPLACE.M with the given input arguments.
%
%      EPLACE('Property','Value',...) creates a new EPLACE or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before eplace_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to eplace_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES
%
% 

% Edit the above text to modify the response to help eplace

% Last Modified by GUIDE v2.5 08-Apr-2019 15:47:09

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @eplace_OpeningFcn, ...
                   'gui_OutputFcn',  @eplace_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
               
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before eplace is made visible.
function eplace_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
% varargin   command line arguments to eplace (see VARARGIN)

options = struct( 'mri', '',...
    'label', '',...
    'maskdir', '',...
    'gui_mode', 'non-interactive');
options = G_SparseArgs( options, varargin);
    
handles.init_img = options.mri;

labels = ReadLabel( options.label);
if ~isempty( labels)
    set( handles.dest_label, 'String', labels);
end

handles.gui_mode = options.gui_mode;
switch handles.gui_mode
    case { 'non-interactive', 'interactive'}
        % do nothing
    otherwise
        handles.gui_mode = 'interactive';
end

handles.fontsize = 8;

% automatic labels directory
handles.maskdir = options.maskdir;

% Choose default command line output for eplace
handles.output = hObject;
handles = InitilizeHandles( handles);
handles = SetOriLabel( handles);
% handles.userdata.lut = FSColorLUT;

% make everything invisible
set( findall( hObject, '-property', 'Enable'), 'enable', 'off');
set( findall( hObject, '-property', 'Visible'), 'visible', 'off');
set( findobj( hObject, 'type', 'uimenu'), 'visible', 'on', 'enable', 'on');
set( findobj( hObject, 'tag', 'file_save'), 'enable', 'off');
set( findobj( hObject, 'tag', 'load_elec_mask'), 'enable', 'off');
set( findobj( hObject, 'tag', 'load_elect'), 'enable', 'off');
set( findobj( hObject, 'tag', 'menu_load_label'), 'enable', 'off');

% set pointer to be crosshair
set( handles.figure1, 'Pointer', 'crosshair');

% Update handles structure
guidata( hObject, handles);

% UIWAIT makes eplace wait for user response (see UIRESUME)
if strcmpi( handles.gui_mode, 'interactive')    
    uiwait( handles.figure1);
end

if exist( handles.init_img, 'file')
    % open existing file regardless of gui_mode value
    file_open_Callback( handles.file_open, [], handles);
end

    % Setup default values
    function handles = InitilizeHandles( handles)
        handles.axh(1) = handles.axes1;
        handles.axh(2) = handles.axes2;
        handles.axh(3) = handles.axes3;
        handles.cur_ax = [];
        handles.last_click_ax = [];
                       
        handles.dims = [0 0 0];
        for k = 1 : 3
            handles.userdata.ax(k).xlim = handles.axh(k).XLim;
            handles.userdata.ax(k).ylim = handles.axh(k).YLim;
            handles.userdata.ax(k).raw_xlim = handles.userdata.ax(k).xlim;
            handles.userdata.ax(k).raw_ylim = handles.userdata.ax(k).ylim;
            % boxes field
            handles.box(k).start = 'yes'; %  0, start plotting
            handles.box(k).h = []; % handle to line object
            handles.box(k).data = [];
            handles.box(k).move = 'no';
        end

        % draw mask
        % flag to indicate whehter it's painting or erasing
        handles.draw.status = 'off'; % 'on' | 'off'
        handles.draw.start = 'no';
        handles.draw.pensize = 1; % size of pen
        handles.draw.penval = 1; % intensity of the pen
        handles.draw.mask = []; % index x val
        handles.draw.history = {}; % Ctrl+Z to roll back {action_name, index; action_name, index; ...}
        handles.draw.ctable = []; % color table
        handles.draw.cmat = []; % color table index
        handles.draw.linecolor = 'w';
        handles.draw.linewidth = 1.5;
        handles.draw.colormap = [1, 0 0];
        set( handles.draw_mask, 'Value', 0);
        set( handles.pen_val, 'String', num2str( handles.draw.penval));

        handles.userdata.axes_click = 'no';
        handles.userdata.yoke_coord = [];
        handles.userdata.rois = {};
        handles.userdata.roiname = {};
        % registeration files
        handles.userdata.reg = '';
        handles.userdata.elec_proj = '';
        handles.userdata.atlas = [];
        set( handles.label_list, 'String', handles.userdata.roiname, 'Value', 0);        
        set( handles.dest_label, 'String', {}, 'Value', 0);
        
        % reserved
        handles.vol_ind = 1;

        % default values for place_label options
        handles.elec.use_peak = 'yes'; % 'yes' | 'no'
        handles.elec.peak_radius =  2;
        handles.elec.peak_type = 'sphere'; % 'sphere' | 'cubic'
        handles.elec.initial_center = 'yes';
        handles.elec.center_threshold = 0.85;    
        handles.elec.center_radius = 1;    
        handles.elec.clust_radius = 5;    
        handles.elec.overlap_threshold = 0.9;    
        handles.elec.sigma = 0.2;    
        handles.elec.use_exact = 'no';
        handles.elec.find_peak = 'no';
        % electrode transprancy
        handles.elec.elec_transp = 1;

        set( handles.use_peak, 'Value', 1);
        set( handles.peak_type, 'Value', 1);
        set( handles.peak_radius, 'String', num2str( handles.elec.peak_radius));
        set( handles.initial_center, 'Value', 1);
        set( handles.center_radius, 'String', num2str( handles.elec.center_radius));
        set( handles.overlap_threshold, 'String', num2str( handles.elec.overlap_threshold));
        set( handles.sigma, 'String', num2str( handles.elec.sigma));
        set( handles.clust_radius, 'String', num2str( handles.elec.clust_radius));
        set( handles.use_exact, 'Value', 0);
        set( handles.find_peak, 'Value', 0);
        set( handles.initial_center_threshold, 'String', num2str( handles.elec.center_threshold));

        handles.results_saved = 'no';               
        
        
% --- Outputs from this function are returned to the command line.
function varargout = eplace_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Get default command line output from handles structure
if strcmpi( handles.gui_mode, 'interactive') 
    if strcmpi( get( handles.output, 'waitstatus'), 'waiting')
        % do nothing
    else
        varargout{1} = GetResults( handles);
        delete( handles.figure1);
        if isfield( handles, 'yoke') && isvalid( handles.yoke)
            close( ghandles.yoke.Parent)
        end
        
        if isfield( handles.userdata.plot.surf, 'ax')...
                && isvalid( handles.userdata.plot.surf.ax)
            close( get( handles.userdata.plot.surf.ax, 'Parent'))
        end    
    end    
else
    varargout{1} = handles.output;
end

function img_coordx_Callback(hObject, eventdata, handles)
% hObject    handle to img_coordx (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of img_coordx as text
%        str2double(get(hObject,'String')) returns contents of img_coordx as a double
val = round( str2double( hObject.String));
if isscalar( val) && ~isnan( val) && val >= 1 && val <= handles.dims(1)
    handles.mriinfo.i = val;
    tmp = handles.mri.vox2ras1 * ...
        [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
    handles.mriinfo.std_coord = tmp( 1:3);
    guidata( hObject, handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function img_coordx_CreateFcn(hObject, eventdata, handles)
% hObject    handle to img_coordx (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor', 'white');
end

function img_coordy_Callback(hObject, eventdata, handles)
% hObject    handle to img_coordy (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of img_coordy as text
%        str2double(get(hObject,'String')) returns contents of img_coordy as a double
val = round( str2double( hObject.String));
if isscalar( val) && ~isnan( val) && val >= 1 && val <= handles.dims(2)
    handles.mriinfo.j = val;
    tmp = handles.mri.vox2ras1 * ...
        [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
    handles.mriinfo.std_coord = tmp( 1:3);
    guidata( hObject, handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function img_coordy_CreateFcn(hObject, eventdata, handles)
% hObject    handle to img_coordy (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function img_coordz_Callback(hObject, eventdata, handles)
% hObject    handle to img_coordz (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of img_coordz as text
%        str2double(get(hObject,'String')) returns contents of img_coordz as a double
val = round( str2double( hObject.String));
if isscalar( val) && ~isnan( val) && val >= 1 && val <= handles.dims(3)
    handles.mriinfo.k = val;
    tmp = handles.mri.vox2ras1 * ...
        [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
    handles.mriinfo.std_coord = tmp( 1:3);
    guidata( hObject, handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function img_coordz_CreateFcn(hObject, eventdata, handles)
% hObject    handle to img_coordz (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function std_coordx_Callback(hObject, eventdata, handles)
% hObject    handle to std_coordx (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of std_coordx as text
%        str2double(get(hObject,'String')) returns contents of std_coordx as a double
val = str2double( hObject.String);
if isscalar( val) && ~isnan( val)
    val = round( handles.mri.vox2ras1 \ [val; handles.mriinfo.std_coord(2); handles.mriinfo.std_coord(3); 1]);
    if val(1) >= 1 && val(1) <= handles.dims(1)
        handles.mriinfo.i = val(1);
        tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
        handles.mriinfo.std_coord = tmp( 1:3);
        guidata( hObject, handles);
    end
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function std_coordx_CreateFcn(hObject, eventdata, handles)
% hObject    handle to std_coordx (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function std_coordy_Callback(hObject, eventdata, handles)
% hObject    handle to std_coordy (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of std_coordy as text
%        str2double(get(hObject,'String')) returns contents of std_coordy as a double
val = str2double( hObject.String);
if isscalar( val) && ~isnan( val)   
    val = round( handles.mri.vox2ras1 \ [handles.mriinfo.std_coord(1); val; handles.mriinfo.std_coord(3); 1]);
    if val(2) >= 1 && val(2) <= handles.dims(2)
        handles.mriinfo.j = val(2);
        tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
        handles.mriinfo.std_coord = tmp( 1:3);
        guidata( hObject, handles);
    end
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function std_coordy_CreateFcn(hObject, eventdata, handles)
% hObject    handle to std_coordy (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function std_coordz_Callback(hObject, eventdata, handles)
% hObject    handle to std_coordz (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of std_coordz as text
%        str2double(get(hObject,'String')) returns contents of std_coordz as a double
val = str2double( hObject.String);
if isscalar( val)  && ~isnan( val)
    val = round( handles.mri.vox2ras1 \ [handles.mriinfo.std_coord(1); handles.mriinfo.std_coord(2); val; 1]);
    if val(3) >= 1 && val(3) <= handles.dims(3)
        handles.mriinfo.k = val(3);
        tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
        handles.mriinfo.std_coord = tmp( 1:3);
        guidata( hObject, handles);
    end
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function std_coordz_CreateFcn(hObject, eventdata, handles)
% hObject    handle to std_coordz (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in plus_x.
function plus_x_Callback(hObject, eventdata, handles)
% hObject    handle to plus_x (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
handles.mriinfo.i = min( [handles.mriinfo.i + 1, handles.dims(1)]);
tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
redraw( handles);

% --- Executes on button press in minus_x.
function minus_x_Callback(hObject, eventdata, handles)
% hObject    handle to minus_x (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
handles.mriinfo.i = max( [1, handles.mriinfo.i - 1]);
tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
redraw( handles);

% --- Executes on button press in plus_y.
function plus_y_Callback(hObject, eventdata, handles)
% hObject    handle to plus_y (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
handles.mriinfo.j = min( [handles.mriinfo.j + 1, handles.dims(2)]);
tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
redraw( handles);

% --- Executes on button press in minus_y.
function minus_y_Callback(hObject, eventdata, handles)
% hObject    handle to minus_y (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
handles.mriinfo.j = max( [1, handles.mriinfo.j - 1]);
tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
redraw( handles);

% --- Executes on button press in plus_z.
function plus_z_Callback(hObject, eventdata, handles)
% hObject    handle to plus_z (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
handles.mriinfo.k = min( [handles.mriinfo.k + 1, handles.dims(3)]);
tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
redraw( handles);

% --- Executes on button press in minus_z.
function minus_z_Callback(hObject, eventdata, handles)
% hObject    handle to minus_z (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
handles.mriinfo.k = max( [1, handles.mriinfo.k - 1]);
tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
redraw( handles);

function mag_edit_Callback(hObject, eventdata, handles)
% hObject    handle to mag_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of mag_edit as text
%        str2double(get(hObject,'String')) returns contents of mag_edit as a double
val = str2double( strtok( hObject.String, '%'));
if length( val) > 1 || isnan( val) || val <= 0 || val >= 100000
    set( hObject, 'String', num2str( handles.mag));
    return;
end

handles.mag = val;
if abs( val - 100) < eps
    % default view
    for ax_idx = 1 : 3
        handles.userdata.ax( ax_idx).xlim = handles.userdata.ax( ax_idx).raw_xlim;
        handles.userdata.ax( ax_idx).ylim = handles.userdata.ax( ax_idx).raw_ylim;
    end
    
else    
    val = 100/val;
    for ax_idx = 1 : 3
        xlim_r = diff( handles.userdata.ax( ax_idx).raw_xlim);
        ylim_r = diff( handles.userdata.ax( ax_idx).raw_ylim);        
        new_xlim = 0.5 * val * xlim_r;
        new_ylim = 0.5 * val * ylim_r;        
        if ax_idx == 1
            handles.userdata.ax( ax_idx).xlim = handles.mriinfo.j + [-1, 1]*new_xlim;
            handles.userdata.ax( ax_idx).ylim = handles.mriinfo.k + [-1, 1]*new_ylim;
        elseif ax_idx==2
            handles.userdata.ax( ax_idx).xlim = handles.mriinfo.i + [-1, 1]*new_xlim;
            handles.userdata.ax( ax_idx).ylim = handles.mriinfo.k + [-1, 1]*new_ylim;
        else
            handles.userdata.ax( ax_idx).xlim = handles.mriinfo.i + [-1, 1]*new_xlim;
            handles.userdata.ax( ax_idx).ylim = handles.mriinfo.j + [-1, 1]*new_ylim;
        end
    end
end
guidata( hObject, handles);
redraw( handles);

function intensity_min_Callback(hObject, eventdata, handles)
% hObject    handle to intensity_min (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of intensity_min as text
%        str2double(get(hObject,'String')) returns contents of intensity_min as a double
cur_clim = handles.clim;
new_lo = str2double( hObject.String);
if isscalar( new_lo) && ~isnan( new_lo)
    handles.clim = [new_lo, cur_clim(2)];
    guidata( hObject, handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function intensity_min_CreateFcn(hObject, eventdata, handles)
% hObject    handle to intensity_min (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function intensity_max_Callback(hObject, eventdata, handles)
% hObject    handle to intensity_max (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% Hints: get(hObject,'String') returns contents of intensity_max as text
%        str2double(get(hObject,'String')) returns contents of intensity_max as a double
cur_clim = handles.clim;
new_hi = str2double( hObject.String);
if isscalar( new_hi) && ~isnan( new_hi)
    handles.clim = [cur_clim(1), new_hi];
    guidata( hObject, handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function intensity_max_CreateFcn(hObject, eventdata, handles)
% hObject    handle to intensity_max (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --------------------------------------------------------------------
function file_Callback(hObject, eventdata, handles)
% hObject    handle to file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% --------------------------------------------------------------------
function Open_Callback(hObject, eventdata, handles)
% hObject    handle to Open (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% --------------------------------------------------------------------
function file_open_Callback(hObject, eventdata, handles)
% hObject    handle to file_open (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

if isempty( handles.init_img)
    [filename, p] = uigetfile( '*.nii.gz', 'Select CT image');
    if filename == 0
        return;
    end
    handles = InitilizeHandles( handles);
    mri = fullfile( p, filename);

else
    % calling with input arguments
    handles = InitilizeHandles( handles);
    mri = handles.init_img;
    handles.init_img = '';
end

handles.src_img = mri;

% load image
try
    set( handles.coord_space_name, 'enable', 'on', 'visible', 'on');
    set( handles.coord_space_name, 'String', ['Loading ... ', mri]);
    drawnow;
    mri = MRIread( mri);    
catch
    fprintf( ['Failed to open ', mri(:)']);
    set( handles.coord_space_name, 'String', ['Error: Failed to open ', mri(:)'], 'visible', 'on');
    drawnow;
    return;
end

if size( mri.vol, 4) ~= 1
    fprintf( 'Error: Input must be a 3d image.\n');
    set( handles.coord_space_name, 'String', 'Error: Input must be a 3d image.', 'visible', 'on');
    drawnow;
    return;
end

% resolution
mri.vol = permute( mri.vol, [2 1 3 4]);
resol = mri.volres( [2 1 3]);
handles.voxsz = resol;

% starting point
sz = size( mri.vol);
cross_coord = round( sz/2);
handles.mriinfo.i = cross_coord(1);
handles.mriinfo.j = cross_coord(2);
handles.mriinfo.k = cross_coord(3);
tmp = mri.vox2ras1 * [cross_coord(1:3), 1]';
handles.mriinfo.std_coord = tmp(1:3);

handles.dims = sz;
handles.mri = mri( :, :, :, handles.vol_ind);

handles.userdata.ax(1).xlim = [1, sz(2)];
handles.userdata.ax(1).ylim = [1, sz(3)];
handles.userdata.ax(1).aspectratio = resol( [3, 2, 3]);

handles.userdata.ax(2).xlim = [1, sz(1)];
handles.userdata.ax(2).ylim = [1, sz(3)];
handles.userdata.ax(2).aspectratio = resol( [3, 1, 2]);

handles.userdata.ax(3).xlim = [1, sz(1)];
handles.userdata.ax(3).ylim = [1, sz(2)];
handles.userdata.ax(3).aspectratio = resol( [2, 1, 3]);

for k = 1:3
    handles.userdata.ax(k).raw_xlim = handles.userdata.ax(k).xlim;
    handles.userdata.ax(k).raw_ylim = handles.userdata.ax(k).ylim;
end

% initial_mag
handles.mag = 100;
% intensity range
handles.clim = prctile( handles.mri.vol(:), [10, 99.5]);

% initialized colortable
[cmat, ctable] = ColorTable( [], handles.dims);
handles.cmat = cmat;
handles.c = ctable;

% display orientation infomation
set( handles.coord_space_name, 'String', '');
% % show image
% redraw( handles);
handles = SetOriLabel( handles);
% drawnow;

% enable all objects
set( findall( handles.figure1, '-property', 'Enable'), 'enable', 'on');
set( findall( handles.figure1, '-property', 'Visible'), 'visible', 'on');
% except those
handles = SelfHandles( handles);

% change background color of edit boxes
set( [handles.label_name, ...
    handles.mag_edit, ...
    handles.intensity_min,...
    handles.intensity_max,...
    handles.peak_radius,...
    handles.center_radius,...
    handles.initial_center_threshold,...
    handles.overlap_threshold,...
    handles.clust_radius,...
    handles.sigma,...
    handles.img_coordx,...
    handles.img_coordy,...
    handles.img_coordz,...
    handles.std_coordx,...
    handles.std_coordy,...
    handles.std_coordz], 'backgroundcolor', [1 1 1] * 0.2);

guidata( hObject, handles);
redraw( handles);

% try automatic mask
if ~isempty( handles.maskdir)
    load_elec_mask_Callback(hObject, eventdata, handles, handles.maskdir);
end
   

	function handles = InitializeYoke( handles)
        % update yoke figure for each call of this function
        f = findobj( 'name', 'mriviewer_coords');
        if length( f) ~= 1 || ~strcmpi( f.Type, 'figure')
            f = figure( 'units', 'normalized',...
                'position', [0.01 0.6 0.2 0.35],...
                'name', 'mriviewer_coords',...
                'numbertitle', 'off');
            handles.yoke = axes( f);
            axis( handles.yoke, 'off');
            axis( handles.yoke, 'equal');
            axis( handles.yoke, 'vis3d');
        
        else
            aa = findobj( f.Children, 'type', 'axes');
            if isempty( aa)
                handles.yoke = axes( f);
            elseif length( aa) > 1
                delete( aa(2:end));
            else
                handles.yoke = aa;
            end
            cla( handles.yoke);
        end        
        
	function handles = SelfHandles( handles)
        set( handles.dest_label,...
            'enable', 'off',...
            'visible', 'off');
        set( handles.real_label_text,...
            'enable', 'off',...
            'visible', 'off');
        set( handles.rename_label,...
            'enable', 'off',...
            'visible', 'off');
        set( [handles.draw_mask, handles.pen_val, handles.pen_sz],...
            'enable', 'off',...
            'visible', 'off');
  
	function handles = SetOriLabel( handles)
        % orientation label
        if isfield( handles, 'mri')
            labels = { {'P', 'A'},...
                {'L', 'R'},...
                {'I', 'S'}};
            vec = [handles.mri.x_a, handles.mri.x_r, handles.mri.x_s];
            [~, midx] = max( abs( vec));
            s = cell( 1, 6);
            if vec( midx) > 0
                s(1:2) = labels{ midx}( [1, 2]);
            else
                s(1:2) = labels{ midx}( [2, 1]);
            end
            
            vec = [handles.mri.y_a, handles.mri.y_r, handles.mri.y_s];
            [~, midx] = max( abs( vec));
            if vec( midx) > 0
                s(3:4) = labels{ midx}( [1, 2]);
            else
                s(3:4) = labels{ midx}( [2, 1]);
            end
            
            vec = [handles.mri.z_a, handles.mri.z_r, handles.mri.z_s];
            [~, midx] = max( abs( vec));
            if vec( midx) > 0
                s(5:6) = labels{ midx}( [1, 2]);
            else
                s(5:6) = labels{ midx}( [2, 1]);
            end
            
        else
            s = { '', '', '', '', '', ''};
        end
        
        % set orientation labels
        set( handles.lbl2L, 'String', s{1});
        set( handles.lbl2R, 'String', s{2});
        set( handles.lbl3L, 'String', s{1});
        set( handles.lbl3R, 'String', s{2});
        
        set( handles.lbl1L, 'String',  s{3});
        set( handles.lbl1R, 'String', s{4});
        set( handles.lbl3B, 'String',  s{3});
        set( handles.lbl3T, 'String', s{4});
        
        set( handles.lbl1B, 'String', s{5});
        set( handles.lbl1T, 'String', s{6});
        set( handles.lbl2B, 'String',  s{5});
        set( handles.lbl2T, 'String',  s{6});

        set( [handles.lbl2L,...
            handles.lbl2R,...
            handles.lbl3L,...
            handles.lbl3R,...
            handles.lbl1L,...
            handles.lbl1R,...
            handles.lbl3B,...
            handles.lbl3T,...
            handles.lbl1B,...
            handles.lbl1T,...
            handles.lbl2B,...
            handles.lbl2T], 'enable', 'on', 'visible', 'on');

% --------------------------------------------------------------------
function elec = file_save_Callback(hObject, eventdata, handles)
% hObject    handle to file_save (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
elec = GetResults( handles);
uisave( 'elec', 'elecpos');
handles.results_saved = 'yes';
guidata( hObject, handles);

    function elec = GetResults( handles)
        set( handles.coord_space_name, 'String', 'Retrieving results');
        drawnow;
        
        elec = [];
        if isfield( handles, 'mri')
            elec.rois = handles.userdata.rois;
            elec.label = handles.userdata.roiname;
            
            % sort labels
            [sorted_str, sorted_idx] = SortStr( elec.label);
            elec.label = sorted_str;
            elec.rois = elec.rois( sorted_idx);

            elec.coord.img2mm = handles.mri.vox2ras1;
            elec.coord.dims = handles.dims;
            
            % for backward compatiblity
            if ~isempty( handles.userdata.reg)
                elec.reg = handles.userdata.reg;
            end
            if ~isempty( handles.userdata.elec_proj)
                elec.proj = handles.userdata.elec_proj;
            end
            if ~isempty( handles.userdata.atlas)
                elec.atlas = handles.userdata.atlas;
            end
            
            % innominate files
            username = getenv( 'USER');
            elec.coord.src_img = strrep( handles.src_img, ['/Users/', username], '~');
            
            % get max, mess center etc
            [X, Y, Z] = ndgrid( 1:handles.dims(1), 1:handles.dims(2), 1:handles.dims(3));
            X = X(:);
            Y = Y(:);
            Z = Z(:);
            elec.coord.peak = [];
            elec.coord.unweighted_center = [];
            elec.coord.weighted_center = [];
            elec.coord.img_peak = [];
            elec.coord.img_unweighted_center = [];
            elec.coord.img_weighted_center = [];
            for roi_idx = 1 : length( elec.rois)
                roi_ind = elec.rois{ roi_idx};
                val = handles.mri.vol( roi_ind);
                [~, midx] = max( val);
                [xx, yy, zz] = ind2sub( handles.dims, roi_ind( midx));
                elec.coord.img_peak( roi_idx, 1:3) = [xx, yy, zz];

                pk_img = handles.mri.vox2ras1 * [xx;yy;zz; 1];   
                elec.coord.peak( roi_idx, 1:3) = pk_img( 1:3);

                val = val ./ sum( val);        
                roi_x = X( roi_ind);
                roi_y = Y( roi_ind);
                roi_z = Z( roi_ind);

                % unweighted center
                c = mean( [roi_x, roi_y, roi_z], 1);
                weight_c = [roi_x' *val(:), roi_y' *val(:), roi_z' *val(:)];
                elec.coord.img_unweighted_center( roi_idx, 1:3) = c;
                elec.coord.img_weighted_center( roi_idx, 1:3) = weight_c;

                c_img = handles.mri.vox2ras1 * [c(:); 1];
                elec.coord.unweighted_center( roi_idx, 1:3) = c_img( 1:3);

                weight_c_img = handles.mri.vox2ras1 * [weight_c(:); 1];
                elec.coord.weighted_center( roi_idx, 1:3) = weight_c_img( 1:3);  
            end
            
            % use unweighted center in mm as default
            elec.elecpos.coord = elec.coord.unweighted_center;
            elec.elecpos.coord_type = 'unweighted_center';
                       
            % hand-drawn ROIs
            elec.mask = handles.draw.mask;
            
        end % MRI was set
   
        
% --- Executes during object creation, after setting all properties.
function axes1_CreateFcn(hObject, eventdata, handles)
% hObject    handle to axes1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: place code in OpeningFcn to populate axes1


% --- Executes during object creation, after setting all properties.
function axes2_CreateFcn(hObject, eventdata, handles)
% hObject    handle to axes2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: place code in OpeningFcn to populate axes2

function CrossHair( h, img_h, pnt)
%    h, handle to axes
%   img_h, handle to imagesc object
%   pnt, [x, y] point
    x = pnt(1);
    y = pnt(2);    
    crosshair_color = [1 1 1];
    crosshair_linewidth = 1;  
    xlim = get( h, 'xlim');
    ylim = get( h, 'ylim');
    
    [~, ~, xpixel_width, ypixel_width] = GetImgInfo( img_h);
    
    if x == xlim(1)
        l_h = line( h, xlim + xpixel_width, [1, 1]*y);        
    elseif x == xlim(2)
        l_h = line( h, [xlim(1), x] - xpixel_width, [1, 1]*y);        
    else
        l_h = line( h,[xlim(1), x] - xpixel_width, [1, 1]*y);
        l_h2 = line( h,[x, xlim(2)] + xpixel_width, [1, 1]*y);
        set( l_h2, 'color', crosshair_color, 'linewidth', crosshair_linewidth);
    end
    set( l_h, 'color', crosshair_color, 'linewidth', crosshair_linewidth);
     
    if y == ylim(1)
        l_h = line( h,[x, x], ylim + ypixel_width);        
    elseif y == ylim(2)
        l_h = line( h,[x, x], [ylim(1), y] - ypixel_width);    
    else
        l_h = line(h, [x, x], [y, ylim(2)] + ypixel_width);
        l_h2 = line(h, [x, x], [ylim(1), y] - ypixel_width);
        set( l_h2, 'color', crosshair_color, 'linewidth', crosshair_linewidth);
    end    
    set( l_h, 'color', crosshair_color, 'linewidth', crosshair_linewidth);
            
    
function  [xlim, ylim, xpixel_width, ypixel_width, xdata, ydata] = GetImgInfo( h)
% h, handle to imagesc object
    [ylim, xlim] = size( get( h, 'CData'));
    [xpixel_width, xdata] = GetPixelWidth( get( h, 'xdata'), xlim);
    [ypixel_width, ydata] = GetPixelWidth( get( h, 'yData'), ylim);

%% Retrieve pixel witdh and height
function [px_width, ydata] = GetPixelWidth( ydata, ylim)
    px_width = 0.5;
    if ylim > 1
        if length( ydata) == 2
            px_width = diff( ydata) / (2*(ylim-1));
            ydata = linspace( ydata(1), ydata(2), ylim);
        elseif length( ydata) > 2
            px_width = diff( ydata) / 2;
        end
        px_width = px_width(1);
    end

% --- Executes on mouse motion over figure - except title and menu.
function figure1_WindowButtonMotionFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
% 
if ~isempty( handles.cur_ax)
    ax_idx = handles.cur_ax;
    cpnt = get( handles.axh(ax_idx), 'CurrentPoint');
    x = cpnt( 1, 1);
    y = cpnt( 1, 2);
    xlim = get( handles.axh( ax_idx), 'xlim');
    ylim = get( handles.axh( ax_idx), 'ylim');
        
    if strcmpi( get( handles.figure1, 'SelectionType'), 'normal') 
        x = round( x);
        y = round( y);

        raw_xlim = round( handles.userdata.ax( ax_idx).raw_xlim);
        raw_ylim = round( handles.userdata.ax( ax_idx).raw_ylim);
        %raw_xlim = handles.userdata.ax( handles.cur_ax).raw_xlim;
        raw_xlim(1) = max( ceil( [raw_xlim(1), xlim(1)]));
        raw_xlim(2) = min( floor( [raw_xlim(2), xlim(2)]));
        if x < raw_xlim(1)
            x = raw_xlim(1);
        elseif x > raw_xlim(2)
            x = raw_xlim(2);
        end

        % raw_ylim = handles.userdata.ax( handles.cur_ax).raw_ylim;
        raw_ylim(1) = max( ceil( [raw_ylim(1), ylim(1)]));
        raw_ylim(2) = min( floor( [raw_ylim(2), ylim(2)]));
        if y < raw_ylim(1)
            y = raw_ylim(1);
        elseif y > raw_ylim(2)
            y = raw_ylim(2);
        end

        % update image plot
        if isfield( handles, 'mri')
            if handles.cur_ax == 1
                handles.mriinfo.j = x;
                handles.mriinfo.k = y;  
                pen_loc = [handles.mriinfo.i, x, y];

            elseif handles.cur_ax == 2
                handles.mriinfo.i = x;
                handles.mriinfo.k = y;
                pen_loc = [x, handles.mriinfo.j, y]; 

            else
                handles.mriinfo.i = x;
                handles.mriinfo.j = y;
                pen_loc = [x, y, handles.mriinfo.k];
            end
                       
            if strcmpi( handles.draw.start, 'no')
                tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
                handles.mriinfo.std_coord = tmp( 1:3);
                guidata( hObject, handles);
                % redraw( handles);
                
            else
                pen_ind = sub2ind( handles.dims, pen_loc(1), pen_loc(2), pen_loc(3));
                % draw current ROI
                if handles.draw.penval > 0
                    if isempty( handles.draw.mask)
                        handles.draw.mask = [pen_ind, handles.draw.penval];  

                    else
                        if sum( handles.draw.mask(:,1) == pen_ind) == 1
                            handles.draw.mask( handles.draw.mask( :,1) == pen_ind, 2) = handles.draw.penval;
                        else
                            handles.draw.mask = cat( 1, handles.draw.mask, [pen_ind, handles.draw.penval]);
                        end
                    end  
                    
                else
                    if ~isempty( handles.draw.mask)
                        handles.draw.mask( handles.draw.mask( :, 1) == pen_ind, :) = [];
                    end
                end
                            
                for ax_idx = 1 : 3
                    if ax_idx == 1
                        xdata = pen_loc(2) + handles.draw.img_info( ax_idx, 1)*[-1, 1, 1, -1, -1];
                        ydata = pen_loc(3) + handles.draw.img_info( ax_idx, 2)*[-1, -1, 1, 1, -1];
                    elseif ax_idx == 2
                        xdata = pen_loc(1) + handles.draw.img_info( ax_idx, 1)*[-1, 1, 1, -1, -1];
                        ydata = pen_loc(3) + handles.draw.img_info( ax_idx, 2)*[-1, -1, 1, 1, -1];
                    else
                        xdata = pen_loc(1) + handles.draw.img_info( ax_idx, 1)*[-1, 1, 1, -1, -1];
                        ydata = pen_loc(2) + handles.draw.img_info( ax_idx, 2)*[-1, -1, 1, 1, -1];
                    end
                    handles.draw.h( ax_idx, 1) = line( handles.axh( ax_idx), xdata, ydata);
                    set( handles.draw.h( ax_idx),...
                        'color', handles.draw.linecolor,...
                        'linewidth', handles.draw.linewidth);
                end
            
                guidata( hObject, handles);
            end
            
        end % mri set
               

    elseif strcmpi( get( handles.figure1, 'SelectionType'), 'alt')
        % right click
        if ~isempty( handles.box( ax_idx).h) && strcmpi( handles.box( ax_idx).start, 'no')
            % plot new box
            xData = get( handles.box( ax_idx).h, 'xData');
            yData = get( handles.box( ax_idx).h, 'yData');
            if x < xlim(1)
                x = xlim(1);
            elseif x > xlim(2)
                x = xlim(2);
            else
                % do nothing
            end
            
            if y < ylim(1)
                y = ylim(1);
            elseif y > ylim(2)
                y = ylim(2);
            else
                % do nothing
            end

            xData( 2:3) = x;  
            yData( 3:4) = y;
            set( handles.box( ax_idx).h, 'xData', xData, 'yData', yData);
            handles.box( ax_idx).data = {xData, yData};
            % fprintf( 'current boundary: %s, %s\n', num2str( min( xData([1 3]))), num2str( max( xData([1 3]))));

        elseif ~isempty( handles.box( ax_idx).data) ...
                && strcmpi( handles.box( ax_idx).move, 'yes')
            xData = handles.box( ax_idx).data{1};
            yData = handles.box( ax_idx).data{2};
            % move box, to-do
            d = sort( xData);            
            d = ( d(end) - d(1))/2;
            if x >= xlim(1)+d && x <= xlim(2) - d
                xData = [x-d, x+d, x+d, x-d, x-d];
            end
            
            d = sort( yData);            
            d = ( d(end) - d(1))/2;
            if y >= ylim(1)+d && y <= ylim(2) - d
                yData = y + [-d, -d, d, d, -d];
            end
            
            tmp_h = findobj( handles.axh( ax_idx), 'type', 'line');
            for tmp_idx = 1 : length( tmp_h)
                if strcmpi( get( tmp_h( tmp_idx), 'linestyle'), '--')
                    tmp_h = tmp_h( tmp_idx);
                    break;
                end
            end
            
            set( tmp_h, 'xData', xData, 'yData', yData);
            handles.box( ax_idx).data = {xData, yData};
        else
            % do nothing
        end

        guidata( hObject, handles);
        % redraw will delete the line object
    end % click type  
    
end % current axes

% --- Executes on mouse press over figure background, over a disabled or
% --- inactive control, or over an axes background.
function figure1_WindowButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)

% cursor postion in axes
cpnt = get( handles.figure1, 'CurrentPoint');
handles.cur_ax = [];
for k = 1 : 3
    pos = get( handles.axh(k), 'position');
    
    if cpnt(1, 1) >= pos(1) && cpnt(1, 1) <= pos(1) + pos(3) ...
            && cpnt(1, 2) >= pos(2) && cpnt(1, 2) <= pos(2) + pos(4)
        % click within one of the axeses
        handles.cur_ax = k;
        handles.last_click_ax = k;
        
        pnt = get( handles.axh( k), 'CurrentPoint');
        x = pnt( 1, 1);
        y = pnt( 1, 2);
            
        % if it's right click start plotting box
        if strcmpi( get( handles.figure1, 'SelectionType'), 'alt') 
            if isempty( handles.box( k).data)
                % is box is empty, start plotting
                handles.box( k).start = 'no';                 
                xData = repmat( x, [1, 5]);
                yData = repmat( y, [1, 5]);
                hold on;
                handles.box( k).h = line( xData, yData);
                handles.box( k).data = { xData, yData};
                set( handles.box( k).h, 'linestyle', '--',...
                    'linewidth', 1.5, 'color', [1, 0, 0]);                

            else
                % a box already exists
                xData = sort( handles.box( k).data{1});
                yData = sort( handles.box( k).data{2});

                if strcmpi( within_range( [xData([1 end]), yData([1 end])], [x, y]), 'no')
                    % delete the box if a click was within the axes but outside of the box
                    delete(  handles.box( k).h);
                    handles.box( k).h = [];
                    handles.box( k).data = [];
                    handles.box( k).start = 'yes';  
                    handles.box( k).move = 'no';
                else
                    % enable moving option and change the cursor to "hand"
                    handles.box( k).move = 'yes';
                    set( handles.figure1, 'Pointer', 'hand');
                end                  
            end % whether the box is empty  
        end % right mouse
  
        break;
    end % if click was within one of the axeses
end % axes loop

% draw mask
if isfield( handles, 'mri') && strcmpi( handles.draw.status, 'on') ...
        && strcmpi( get( handles.figure1, 'SelectionType'), 'normal')
    if ~isempty( handles.cur_ax)
        % initialize plot
        handles.draw.start = 'yes';
        handles.draw.init_i = handles.mriinfo.i;
        handles.draw.init_j = handles.mriinfo.j;
        handles.draw.init_k = handles.mriinfo.k;
        
        x = round( x);
        y = round( y);
        if handles.cur_ax == 1           
            pen_loc = {handles.mriinfo.i, x, y};             
        elseif handles.cur_ax == 2 
            pen_loc = {x, handles.mriinfo.j, y};            
        else
            pen_loc = {x, y, handles.mriinfo.k};
        end
        pen_ind = sub2ind( handles.dims, pen_loc{1}, pen_loc{2}, pen_loc{3});
        
        % painting or erase mode
        if handles.draw.penval >= 1 
            pen_val = repmat( handles.draw.penval, length( pen_ind), 1);
            if isempty( handles.draw.mask)
                handles.draw.mask = [pen_ind(:), pen_val];  
                
            else
                if sum( handles.draw.mask(:,1) == pen_ind) == 1
                    handles.draw.mask( handles.draw.mask( :,1) == pen_ind, 2) = handles.draw.penval;
                else
                    handles.draw.mask = cat( 1, handles.draw.mask, [pen_ind(:), pen_val]);
                end
            end
            
        else
            if ~isempty( handles.draw.mask)
                handles.draw.mask( handles.draw.mask( :, 1) == pen_ind, :) = [];
            end
        end
        
        for ax_idx = 1 : 3
            hold( handles.axh( ax_idx), 'on');
            img_h = findobj( handles.axh( ax_idx), 'type', 'image');
            [~, ~, xpixel_width, ypixel_width] = GetImgInfo( img_h(1));      
            xdata = [];
            ydata = [];
            if ax_idx == 1
                pl1 = 2;
                pl2 = 3;
            elseif ax_idx == 2
                pl1 = 1;
                pl2 = 3;
            else
                pl1 = 1;
                pl2 = 2;
            end
            
            for kk = 1 : length( pen_loc{1})
                xdata = cat( 2, xdata, pen_loc{ pl1}( kk) + xpixel_width*[-1, 1, 1, -1, -1]);
                ydata = cat( 2, ydata, pen_loc{ pl2}( kk) + ypixel_width*[-1, -1, 1, 1, -1]);
            end            
            
            handles.draw.img_info( ax_idx, 1:2) = [xpixel_width, ypixel_width];
            handles.draw.h( ax_idx, 1) = line( handles.axh( ax_idx), xdata, ydata);
            set( handles.draw.h( ax_idx),...
                'color', handles.draw.linecolor, 'linewidth', handles.draw.linewidth);
        end
    
    end % current axes
end % draw mask

guidata( hObject, handles);


    function UpdateMaskPlot( handles, varargin)
        if ~isempty( handles.draw.mask)
            if ~isempty( varargin)
                handles.draw.mask = handles.draw.mask(  handles.draw.mask(:,2) == varargin{1}, :);
            end
            
            roi_idx = unique( handles.draw.mask( :, 2));
            nbrois = length( roi_idx);
            for kk = 1 : nbrois     
                ind = handles.draw.mask( :, 2) == roi_idx( kk);
                tmp = zeros( handles.dims);
                tmp( handles.draw.mask( ind, 1)) = roi_idx(kk);
                cross_coord_ind = {[2, 3], [1, 3], [1, 2]};
                for ax_idx = 1 : 3
                    cur_ax = handles.axh(ax_idx);
                    hold( cur_ax, 'on');
                    % overlay labels
                    c = cross_coord_ind{ ax_idx}( [2 1]);
                    if ax_idx == 1
                        m = squeeze( tmp( handles.mriinfo.i, :, :))';
                    elseif ax_idx == 2
                        m = squeeze( tmp( :, handles.mriinfo.j, :))';
                    else
                        m = squeeze( tmp( :, :, handles.mriinfo.k))';
                    end

                    if any( m(:))
                        green = handles.draw.colormap( kk, :);
                        nn = zeros( handles.dims(c(1)), handles.dims( c(2)), 3);
                        nn(:,:,1) = green(1);
                        nn(:,:,2) = green(2);
                        nn(:,:,3) = green(3);    
                        
                        hold( cur_ax, 'on');
                        img_h = imagesc( cur_ax, nn);                        
                        set( img_h, 'AlphaData', m > 0);
                        hold( cur_ax, 'off');    
                    end      
                    hold( cur_ax, 'off');

                end % axes loop
            end % roi loop            
        end % plot


% --- Executes on mouse press over figure background, over a disabled or
% --- inactive control, or over an axes background.
function figure1_WindowButtonUpFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user handles (see GUIDATA)
if ~isfield( handles, 'mri')
    return;
end

set( handles.figure1, 'Pointer', 'crosshair');
update_plot = 'no';
handles.userdata.axes_click = 'no';
if ~isempty( handles.cur_ax)
    ax_idx = handles.cur_ax;
    cur_ax = handles.axh( ax_idx);
    cpnt = get( cur_ax, 'CurrentPoint');
    x = round( cpnt(1, 1));
    y = round( cpnt(1, 2));

    if isobject( handles.box( ax_idx).h)
        delete(  handles.box( ax_idx).h);
        handles.box( ax_idx).h = [];
    end
    handles.box( ax_idx).h = [];
    handles.box( ax_idx).start = 'yes';  
    handles.box( ax_idx).move = 'no';
                  
    if strcmpi( get( handles.figure1, 'SelectionType'), 'normal')  
        % a click within the axes was made
        if x >= 1 ...
                && x <= handles.userdata.ax( handles.cur_ax).raw_xlim(2)...
                && y >= 1 && y <= handles.userdata.ax( handles.cur_ax).raw_ylim(2)
            % button up point was within one of the axeses
            if handles.cur_ax == 1
                handles.mriinfo.j = x;
                handles.mriinfo.k = y;     
            elseif handles.cur_ax == 2
                handles.mriinfo.i = x;
                handles.mriinfo.k = y;
            else
                handles.mriinfo.i = x;
                handles.mriinfo.j = y;
            end
            handles.last_click_ax = handles.cur_ax;
            
        else
            handles.last_click_ax = [];
        end
        
        handles.userdata.axes_click = 'yes';        
        update_plot = 'yes';
        
    elseif strcmpi( get( handles.figure1, 'SelectionType'), 'alt') 
        update_plot = 'yes';
        
    end % left click   
    
end % current axes

% set axes selected to none
handles.cur_ax = [];

if strcmpi( handles.draw.start, 'yes')
     handles.draw.start = 'no';
     handles.mriinfo.i = handles.draw.init_i;
     handles.mriinfo.j = handles.draw.init_j;
     handles.mriinfo.k = handles.draw.init_k;     
     for ax_idx = 1 : 3
         delete( handles.draw.h( ax_idx));
     end
     update_plot = 'yes';
end

tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
handles.mriinfo.std_coord = tmp( 1:3);
guidata( hObject, handles);
if strcmpi( update_plot, 'yes')
    redraw( handles);
end
        
% main plot function
function redraw( handles, varargin)       
    if ~isfield( handles, 'mri')
        return;
    end
    figure( handles.output); 

    if nargin > 1
        % preview label
        clust_ind_in_raw = varargin{1};
        [cmat, ctable] = ColorTable( {clust_ind_in_raw}, handles.dims);
        
    else
        if isfield( handles, 'cmat')            
            cmat = handles.cmat;
            ctable = handles.c;
        else
            cmat = zeros( handles.dims);
            ctable = rand( 1, 3);
        end
    end

    sz = handles.dims;
    i = handles.mriinfo.i;
    j = handles.mriinfo.j;
    k = handles.mriinfo.k;
           
    % x&y lims sets will take effect for next call
    h = UpdateXYLims( handles);
    
    % two draws on the first two axeses defien a cubic
    % use ax(1)-xData for y, ax(1)-yData for z, ax(2)-xData for x
    [xData, yData, zData] = RetriveLimsFromBox( handles.box);
    
    cross_coord_ind = {[2, 3], [1, 3], [1, 2]};
    coords = [i, j, k]; 
    for ax_idx = 1 : 3
        cur_ax = handles.axh(ax_idx);
        if ax_idx == 1
            img_h = imagesc( cur_ax, squeeze( handles.mri.vol( i, :, :))'); 
            m = squeeze( cmat( i, :, :))';
        elseif ax_idx == 2
            img_h = imagesc( cur_ax, squeeze( handles.mri.vol( :, j, :))'); 
            m = squeeze( cmat( :, j, :))';
        else
            img_h = imagesc( cur_ax, squeeze( handles.mri.vol( :, :, k))'); 
            m = squeeze( cmat( :, :, k))';
        end
        
        axis( cur_ax, 'off');
        axis( cur_ax, 'equal');
        axis( cur_ax, 'vis3d');
        set( cur_ax, 'DataAspectRatio', handles.userdata.ax( ax_idx).aspectratio,...
            'xlim', h( ax_idx).xlim,...
            'ylim', h( ax_idx).ylim,...
            'color', [0,0,0],...
            'xtick', [], 'ytick', [],...
            'ydir', 'normal');
        colormap( cur_ax, gray);        
        CrossHair( cur_ax, img_h, coords( cross_coord_ind{ ax_idx}));
        caxis( cur_ax, handles.clim);
        
        % overlay labels
        hold( cur_ax, 'on');
        c = cross_coord_ind{ ax_idx}( [2 1]);
        if any( m(:))
            green = ctable( m, :);
            green = reshape( green, handles.dims(c(1)), handles.dims( c(2)), 3);            
            img_h = imagesc( cur_ax, green);      
            set( img_h, 'AlphaData', handles.elec.elec_transp * (m>1));
        end   

        % hand-drawn boxes
        % original ROI
        if ~isempty( handles.box( ax_idx).data) 
            lh = line( cur_ax, handles.box( ax_idx).data{1}, handles.box( ax_idx).data{2});
            set( lh, 'linestyle', '--', 'linewidth', 1.5, 'color', [1, 0, 0]);
        end
        
        % cubic ROI defined by boxes on two out of the three axeses
        if ~isempty( xData) && ~isempty( yData) && ~isempty( zData)
            if ax_idx == 1
                x4plot = yData( [1, 2, 2, 1, 1]);
                y4plot = zData( [1, 1, 2, 2, 1]);
            elseif ax_idx == 2
                x4plot = xData( [1 2 2 1 1]);
                y4plot = zData( [1, 1, 2, 2, 1]);
            else
                x4plot = xData( [1 2 2 1 1]);
                y4plot = yData( [1, 1, 2, 2, 1]);
            end
            
            lh = line( cur_ax, x4plot, y4plot);
            set( lh, 'linestyle', '-', 'linewidth', 2, 'color', [0, 1, 0]);
        end   
        
        hold( cur_ax, 'off');
    end % axes loop
        
    % hand-drawn ROIs
    UpdateMaskPlot( handles);
    
    % voxel coordinates   
    set( handles.img_coordx, 'string', num2str( i));
    set( handles.img_coordy, 'string', num2str( j));
    set( handles.img_coordz, 'string', num2str( k));  
    
    % image coordinates
    std_coord = handles.mriinfo.std_coord;
    std_coordwdisp = round( 100 * std_coord) / 100;    
    set( handles.std_coordx, 'string', num2str( std_coordwdisp(1) ));
    set( handles.std_coordy, 'string', num2str( std_coordwdisp(2) ));
    set( handles.std_coordz, 'string', num2str( std_coordwdisp(3) ));
    
    % intensity at curernt voxel
    val = nan;
    if i >= 1 && i <= sz(1) && j >= 1 && j <= sz(2) && k >= 1 && k <= sz(3)
        val = handles.mri.vol( i, j, k);
    end
    val = round( 100*val)/100;
    set( handles.disp_intensity, 'string', num2str( val));
    
    % intensity contrast
    set( handles.intensity_min, 'String', num2str( handles.clim(1)));
    set( handles.intensity_max, 'String', num2str( handles.clim(2)));
    
    % mag
    set( handles.mag_edit, 'String', [num2str( handles.mag), '%']);
 
    % yoke
    yoke_coord = handles.userdata.yoke_coord;
    if isfield( handles, 'yoke') && isvalid( handles.yoke) && ~isempty( handles.yoke)
        cla( handles.yoke);
        if ~isempty( handles.userdata.yoke_coord)             
            plot3( handles.yoke, yoke_coord( :, 1),...
                yoke_coord( :, 2),...
                yoke_coord( :, 3),...
                'bo', 'markersize', 6, 'markerfacecolor', 'b');
        end
        
        % cursor location
        hold( handles.yoke, 'on');
        c = handles.mri.vox2ras1 * [i; j; k; 1];
        plot3( handles.yoke, c(1), c(2), c(3),'ro',...
            'markersize', 6, 'markerfacecolor', 'r');
        axis( handles.yoke, 'off');
        axis( handles.yoke, 'equal');
        axis( handles.yoke, 'vis3d');
    end

    % highlight label that enclose current cursor when left button press was within axes
    lbl_ind = [];
    if strcmpi( handles.userdata.axes_click, 'yes') && isempty( gco)
        if isfield( handles.userdata, 'rois') && ~isempty( handles.userdata.rois)
            cur_ind = sub2ind( handles.dims, i, j, k);            
            for lbl_idx = 1 : length( handles.userdata.rois)
                if any( handles.userdata.rois{ lbl_idx} == cur_ind)
                    lbl_ind = cat( 2, lbl_ind, lbl_idx);
                end
            end
        end
    end
    
    % update label listbox
    if ~isempty( lbl_ind)
        set( handles.label_list, 'Value', lbl_ind);        
        lbl = handles.userdata.roiname( lbl_ind);
        lbl = lbl(:)';
        lbl = strjoin( lbl, ' ');
        s = (['Current label ([', num2str( lbl_ind), '] / ',...
            num2str( length( handles.userdata.roiname)), '): ', lbl, '.']);
    else
        s = 'No label defined.';
    end
    set( handles.coord_space_name, 'String', s);
    drawnow;
    guidata( handles.figure1, handles);
        
    function [xData, yData, zData] = RetriveLimsFromBox( bh)
        % retrive boundaries from two boxes
        % bh, handles to boxes lines
        xData = []; 
        yData = [];
        zData = [];
        
        if ~isempty( bh(1).data) && ~isempty( bh(2).data)
            xData = sort( bh( 2).data{1});
            xData = xData( [1, end]);
            yData = sort( bh( 1).data{1});
            yData = yData( [1, end]);
            zData = sort( bh( 1).data{2});
            zData = zData( [1, end]);
            
        elseif ~isempty( bh(1).data) && ~isempty( bh(3).data)
            xData = sort( bh( 3).data{1});
            xData = xData( [1, end]);
            yData = sort( bh( 1).data{1});
            yData = yData( [1, end]);
            zData = sort( bh( 1).data{2});
            zData = zData( [1, end]);
            
        elseif ~isempty( bh(2).data) && ~isempty( bh(3).data)
            xData = sort( bh( 2).data{1});
            xData = xData( [1, end]);
            zData = sort( bh( 2).data{2});
            zData = zData( [1, end]);
            yData = sort( bh( 3).data{2});
            yData = yData( [1, end]);
            
        elseif ~isempty( bh(1).data)
            yData = sort( bh( 1).data{1});
            yData = yData( [1, end]);
            zData = sort( bh( 1).data{2});
            zData = zData( [1, end]);
            
        elseif ~isempty( bh(2).data)
            xData = sort( bh( 2).data{1});
            xData = xData( [1, end]);
            zData = sort( bh( 2).data{2});
            zData = zData( [1, end]);
            
        elseif ~isempty( bh(3).data)
            xData = sort( bh( 3).data{1});
            xData = xData( [1, end]);
            yData = sort( bh( 3).data{2});
            yData = yData( [1, end]);
        end
        
        
% --- Executes on selection change in label_list.
function label_list_Callback(hObject, eventdata, handles)
% hObject    handle to label_list (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns label_list contents as cell array
%        contents{get(hObject,'Value')} returns selected item from label_list
val = get( hObject, 'Value');
if isempty( val)
    return;
end

if ~isempty( handles.userdata.roiname) 
    N = length( handles.userdata.roiname);
    if length( val) == 1
        roi = handles.userdata.rois{ val};
        [X, Y, Z] = ind2sub( handles.dims, roi);
        handles.mriinfo.i = round( mean( X));
        handles.mriinfo.j = round( mean( Y));
        handles.mriinfo.k = round( mean( Z));
        % tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
        % fix round error
        tmp = handles.mri.vox2ras1 * [mean( X); mean( Y); mean( Z); 1];
        handles.mriinfo.std_coord = tmp( 1:3);
        guidata( hObject, handles);  
        redraw( handles);
        
        s = (['Current electrode (', num2str( val), '/', num2str( N), '): ',...
            handles.userdata.roiname{ val}, '.']);
        
    else
        if exist( 'G_Cluster1d', 'file')
            x = zeros( 1, N);
            x( val) = 1;
            [~, ~, ~, unsort_clust_idx] = G_Cluster1d( x, 0.5, 'positive');
            str = '';
            for kk = 1 : length( unsort_clust_idx)
                if length( unsort_clust_idx{ kk}) < 3
                    str = [str, ' ', num2str( unsort_clust_idx{ kk})];
                else
                    str = [str, ' ', num2str( unsort_clust_idx{ kk}(1)), ':',...
                        num2str( unsort_clust_idx{ kk}(end))];
                end
            end
            
        else
            str = num2str( val);
        end
        
        str = strtrim( str);
        s = (['Current electrodes: [', str, '] / ', num2str( N), '.']);        
    end

else
    s = '';
end
set( handles.coord_space_name, 'String', s);

% --- Executes during object creation, after setting all properties.
function label_list_CreateFcn(hObject, eventdata, handles)
% hObject    handle to label_list (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: listbox controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in increase_mag.
function increase_mag_Callback(hObject, eventdata, handles)
% hObject    handle to increase_mag (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if ~isfield( handles, 'mri')
    return;
end
val = get( handles.mag_edit, 'String');
val = min( [1000, 10 + str2double( strtok( val, '%'))]);
set( handles.mag_edit, 'String', [num2str( val), '%']);
guidata( hObject, handles);
mag_edit_Callback( handles.mag_edit, [], handles);


% --- Executes on button press in decrease_mag.
function decrease_mag_Callback(hObject, eventdata, handles)
% hObject    handle to decrease_mag (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if ~isfield( handles, 'mri')
    return;
end
val = get( handles.mag_edit, 'String');
val = max( [10, str2double( strtok( val, '%')) - 10]);
set( handles.mag_edit, 'String', [num2str( val), '%']);
guidata( hObject, handles);
mag_edit_Callback( handles.mag_edit, [], handles);

% --- Executes on button press in add_label.
function add_label_Callback(hObject, eventdata, handles)
% hObject    handle to add_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

[clust_ind_in_raw, i, j, k] = PlaceLabel( handles);
% cluster found
if ~isempty( clust_ind_in_raw)   
    % add to label list
    % make sure there's no duplicates
    nb_allrois = length( handles.userdata.rois);
    is_in = 'no';
    for roi_idx = 1 : nb_allrois
        cur_roi = handles.userdata.rois{ roi_idx};
        if length( cur_roi) == length( clust_ind_in_raw)
            if all( sort( clust_ind_in_raw) == sort( cur_roi))
                is_in = 'yes';
                break;
            end
            
        else
            % new electrode partly overlaps with existing ones
            for idx = 1 : length( clust_ind_in_raw)
                if ismember( clust_ind_in_raw( idx), cur_roi)
                    is_in = 'part';
                    break;
                end
            end
        end
    end
    
    if strcmpi( is_in, 'no') || strcmpi( is_in, 'part')
        lbl_name = 'label1';
        if ~isempty( handles.userdata.roiname)
            cnt = 1;
            while ~isempty( LabelLocation( handles.userdata.roiname, lbl_name))
                cnt = cnt + 1;
                lbl_name = ['label', num2str( cnt)];
            end
        end
        
        handles.userdata.rois( length( handles.userdata.rois)+1) = {clust_ind_in_raw};
        handles.userdata.roiname{ length( handles.userdata.roiname) + 1} =  lbl_name;
        set( handles.label_list,...
            'String', handles.userdata.roiname,...
            'Value', length( handles.userdata.roiname));
        
        if strcmpi( is_in, 'part')
            fprintf( 'Label overlaps with existing ones\n');
            h = warndlg( 'Label overlaps with existing ones', 'Add overlapping labels');
            pause( 3);
            if isvalid( h)
                close( h);
            end
        end
        
    else
        fprintf( 'Label alreday exists\n');
        h = warndlg( 'Label already exists', 'No label was added');
        pause( 3);
        if isvalid( h)
            close( h);
        end
    end
    
    handles.mriinfo.i = i;
    handles.mriinfo.j = j;
    handles.mriinfo.k = k;
    tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
    handles.mriinfo.std_coord = tmp( 1:3);
    
    [cmat, ctable] = ColorTable( handles.userdata.rois, handles.dims);
    handles.cmat = cmat;
    handles.c = cat( 1, handles.c, ctable( size( handles.c, 1)+1:end, :));
    
    handles.userdata.yoke_coord = UpdateYokeCoord( handles.dims, handles.mri.vox2ras1, handles.userdata.rois);
    guidata( hObject, handles);
    
    label_list_Callback( handles.label_list, [], handles);
end


function [clust_ind_in_raw, i, j, k] = PlaceLabel( handles, varargin)    
    % find trough, todo
    inv_peak = 'no';
    
    use_peak = handles.elec.use_peak; % 'yes' | 'no'
    peak_radius = handles.elec.peak_radius;
    peak_type = handles.elec.peak_type;
    initial_center = handles.elec.initial_center;
    center_threshold = handles.elec.center_threshold;    
    % center estimate radius
    center_radius = handles.elec.center_radius;    
    clust_radius = handles.elec.clust_radius;    
    % threshold for separating overlaps
    overlap_threshold = handles.elec.overlap_threshold;    
    sigma = handles.elec.sigma;   

    % current location
    i = handles.mriinfo.i;
    j = handles.mriinfo.j;
    k = handles.mriinfo.k;
            
    if get( handles.use_hand_roi, 'Value') == 1
        % hand-drawn ROI
        [xData, yData, zData] = RetriveLimsFromBox( handles.box);
        if isempty( xData) || isempty( yData) || isempty( zData)
            clust_ind_in_raw = [];
            return;

        else
            vec_x = 1 : handles.dims(1);
            vec_y = 1 : handles.dims(2);
            vec_z = 1 : handles.dims(3);
            sel_x = vec_x( vec_x >= xData(1) & vec_x <= xData(2));
            sel_y = vec_y( vec_y >= yData(1) & vec_y <= yData(2));
            sel_z = vec_z( vec_z >= zData(1) & vec_z <= zData(2));
            
            sel_x = sel_x(:);
            sel_y = sel_y( :);
            sel_z = sel_z(:);
            
            val = handles.mri.vol( sel_x, sel_y, sel_z);
            [mval, midx] = max( val(:));
            [ii, jj, kk] = ind2sub( size( val), midx);
            i = sel_x( ii);
            j = sel_y( jj);
            k = sel_z( kk);
        end

    else
        % automatic mode
        % return current location
        if get( handles.use_exact, 'Value') == 1
            clust_ind_in_raw = sub2ind( handles.dims, i, j, k);
            return;
        end

        dims = handles.dims;
        vox_sz = handles.mri.volres;
        [X, Y, Z] = ndgrid( 1:dims(1), 1:dims(2), 1:dims(3));

        % return peak within a sphere
        return_peak = 'no';
        if get( handles.find_peak, 'Value') == 1
            return_peak = 'yes';
            % force to return peak
            use_peak = 'yes';
        end

        if strcmpi( use_peak, 'yes')
            if strcmpi( peak_type, 'sphere')        
                d = sqrt( ((X-i)*vox_sz(2)) .^2 + ((Y-j)*vox_sz(1)) .^2 + ((Z-k)*vox_sz(3)) .^2) <= peak_radius;
                [sel_x, sel_y, sel_z] = SubRange(  find( d(:)), dims);

            else
                d = ceil( peak_radius / vox_sz(2));
                sel_x = max([1, i - d]) : min( [i+d, dims(1)]);
                d = ceil( peak_radius / vox_sz(1));
                sel_y = max([1, j-d]) : min( [j+d, dims(2)]);
                d = ceil( peak_radius / vox_sz(3));
                sel_z = max([1, k-d]) : min( [k+d, dims(3)]);
                
                sel_x = sel_x(:);
                sel_y = sel_y( :);
                sel_z = sel_z(:);
            end

            val = handles.mri.vol( sel_x, sel_y, sel_z);
            if strcmpi( inv_peak, 'yes')
                [mval, midx] = min( val(:));
            else
                [mval, midx] = max( val(:));
            end
            [ii, jj, kk] = ind2sub( size( val), midx);

            % update the location if use max within a sphere was set
            i = sel_x( ii);
            j = sel_y( jj);
            k = sel_z( kk);

            if strcmpi( return_peak, 'yes')        
                clust_ind_in_raw = sub2ind( handles.dims, i, j, k);
                return;
            end
        
        else
            mval = handles.mri.vol( i, j, k);
        end

        if strcmpi( initial_center, 'yes')
            % estimate of an inital center-of-mass center with a small sphere
            d = sqrt( ((X-i)*vox_sz(2)) .^2 + ((Y-j)*vox_sz(1)) .^2 + ((Z-k)*vox_sz(3)) .^2) <= center_radius;    
            [sel_x, sel_y, sel_z] = SubRange(  find( d(:)), dims);
            val = handles.mri.vol( sel_x, sel_y, sel_z);

            % choose a threshold to cluster current sphere
            if center_threshold < 1             
                thresh_val = val >= mval * center_threshold;   
                CC = bwconncomp( thresh_val);    
                clust_idx = RetrieveClustIndex( sel_x, sel_y, sel_z, [i, j, k], CC);        
                ind = CC.PixelIdxList{ clust_idx};        
                [ii, jj, kk] = ind2sub( size( val), ind);

            else
                ind = find( 0*val(:) > -1);
                [ii, jj, kk] = ind2sub( size( val), ind);
            end

            col_val = val( ind);
            col_val = col_val ./ sum( col_val);        
            if any( isnan( col_val))                       
                i = round( mean( sel_x( ii)));
                j = round( mean( sel_y( jj)));
                k = round( mean( sel_z( kk)));
            else        
                i = round( sel_x( ii)' *col_val);
                j = round( sel_y( jj)' *col_val);
                k = round( sel_z( kk)' *col_val);
            end
        end

        % draw a large ROI centered at current location (peak, initial_center,
        % or current location)
        d = sqrt( ((X-i)*vox_sz(2)) .^2 + ((Y-j)*vox_sz(1)) .^2 + ((Z-k)*vox_sz(3)) .^2) <= clust_radius;    
        [sel_x, sel_y, sel_z] = SubRange( find( d(:)), dims);
    end 

    val = handles.mri.vol( sel_x, sel_y, sel_z);

    if overlap_threshold > 1
        % use absolute value
        threshold = min( [mval, overlap_threshold]);
    else
        threshold = mval * overlap_threshold;
    end
    CC = bwconncomp( val >= threshold);    
    clust_idx = RetrieveClustIndex( sel_x, sel_y, sel_z, [i, j, k], CC);
    
    % index of the cluster in raw image
    clust_ind_in_raw = [];
    if ~isempty( clust_idx)      
        if sigma > 0 && get( handles.use_hand_roi, 'Value') == 0
            % smooth the roi to increase its size
            tmp = zeros( size( val));
            tmp( CC.PixelIdxList{ clust_idx}) = 1;     
            volSmooth = imgaussfilt3( tmp, sigma);
            [ii, jj, kk] = ind2sub( size( val), find( volSmooth(:) > 0));            
        else
            [ii, jj, kk] = ind2sub( size( val), CC.PixelIdxList{ clust_idx});
        end
        
        % voxel index in raw 3d image
        clust_ind_in_raw = sub2ind( handles.dims, sel_x( ii), sel_y( jj), sel_z( kk));
    end

        
function [sel_x, sel_y, sel_z] = SubRange( ind, dims)
    [sel_x, sel_y, sel_z] = ind2sub( dims, ind);
    sel_x = min( sel_x) : max( sel_x);
    sel_x = sel_x( :);    
    sel_y = min( sel_y) : max( sel_y);
    sel_y = sel_y( :);    
    sel_z = min( sel_z) : max( sel_z);
    sel_z = sel_z( :);
    
function clust_idx = RetrieveClustIndex( sel_x, sel_y, sel_z, coord, CC)
    % find the index of the cluster
    % cursor location in this subset ROI
    loc_i = find( sel_x == coord(1));
    loc_j = find( sel_y == coord(2));
    loc_k = find( sel_z == coord(3));
    loc = sub2ind( CC.ImageSize, loc_i, loc_j, loc_k);

    % in which cluster
    clust_idx = cellfun( @(x) ismember( loc, x), CC.PixelIdxList, 'UniformOutput', false);
    clust_idx = find( cell2mat( clust_idx));
   
function [cmat, ctable] = ColorTable( rois, dims)
    % handles.draw.mask, a cell array stores all index of rois
    nbrois = length( rois);
    empty_roi = [];
    tmpimg = zeros( dims);
    tmpimg2 = zeros( dims);
    cnt = 0;
    for roi_idx = 1 : nbrois
       ind = rois{ roi_idx};
       if ~isempty( ind)
           tmpimg( ind) = tmpimg( ind) + 1;
           cnt = cnt + 1;
           tmpimg2( ind) = tmpimg2( ind) + cnt;
       else
           empty_roi = cat( 1, empty_roi, roi_idx);
       end    
    end

    % prepare random color table
    if any( tmpimg2(:))
        % overlaps
        tmp = tmpimg > 1;        
        if any( tmp(:))
            % number of overlaps
            val = unique( tmpimg( tmp));    
            N = length( val);
            % non-overlaps index
            tmpimg2 = tmpimg2 .* (1 - tmp);  
            tt = zeros( dims);
            for k = 1 : N
                tt = tt + k*( tmpimg == val( k));
            end
            cmat = tmpimg2 + (tt + cnt * tmp) + 1;
            
        else
            cmat = tmpimg2 + 1;
        end
        
        % random color
        ctable = rand( max( cmat(:)) + 1, 3);

    else
        cmat = ones( dims);
        ctable = rand( 1, 3);
    end



% --- Executes on button press in show_all_label.
function show_all_label_Callback(hObject, eventdata, handles)
% hObject    handle to show_all_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
[cmat, ctable] = ColorTable( handles.userdata.rois, handles.dims);
handles.cmat = cmat;
handles.c = cat( 1, rand( 1, 3), ctable);
guidata( hObject, handles);
redraw( handles);


% --- Executes on button press in remove_label.
function remove_label_Callback(hObject, eventdata, handles)
% hObject    handle to remove_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

val = get( handles.label_list, 'Value');
val = val( val > 0);
if ~isempty( val)
    N = length( handles.userdata.roiname);
    handles.userdata.roiname( val) = [];
    handles.userdata.rois( val) = [];  
    if isempty(  handles.userdata.roiname)
        % all labels were deleted
        set( handles.label_list, 'Value', 0, 'String', {});        
    else
        val = min( [max(val)+1, N]) - length( val);
        set( handles.label_list, 'Value', val, 'String', handles.userdata.roiname);
    end

    [cmat, ctable] = ColorTable( handles.userdata.rois, handles.dims);
    handles.cmat = cmat;
    handles.c = handles.c( 1:size( ctable, 1), :);    
    handles.userdata.yoke_coord = UpdateYokeCoord( handles.dims, handles.mri.vox2ras1, handles.userdata.rois);    
    guidata( hObject, handles);
    redraw( handles);
end


% --- If Enable == 'on', executes on mouse press in 5 pixel border.
% --- Otherwise, executes on mouse press in 5 pixel border or over label_list.
function label_list_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to label_list (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% --- Executes on key press with focus on label_list and none of its controls.
function label_list_KeyPressFcn(hObject, eventdata, handles)
% hObject    handle to label_list (see GCBO)
% eventdata  structure with the following fields (see MATLAB.UI.CONTROL.UICONTROL)
%	Key: name of the key that was pressed, in lower case
%	Character: character interpretation of the key(s) that was pressed
%	Modifier: name(s) of the modifier key(s) (i.e., control, shift) pressed
% handles    structure with handles and user data (see GUIDATA)

% --- Executes on selection change in dest_label.
function dest_label_Callback(hObject, eventdata, handles)
% hObject    handle to dest_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns dest_label contents as cell array
%        contents{get(hObject,'Value')} returns selected item from dest_label


% --- Executes during object creation, after setting all properties.
function dest_label_CreateFcn(hObject, eventdata, handles)
% hObject    handle to dest_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: listbox controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in rename_label.
function rename_label_Callback(hObject, eventdata, handles)
% hObject    handle to rename_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

dest_val = get( handles.dest_label, 'Value');
dest_str = get( handles.dest_label, 'String');
src_val = get( handles.label_list, 'Value');
src_str = get( handles.label_list, 'String');
if ~isempty( src_val) && ~isempty( dest_str) && src_val > 0 && dest_val > 0
    if isempty( LabelLocation( src_str, dest_str{ dest_val}))
        % avoid name conflications
        src_str{ src_val} = dest_str{ dest_val};
        set( handles.label_list, 'String', src_str);
        
        % move dest to next
        dest_val = min([ dest_val+1, length( dest_str)]);
        set( handles.dest_label, 'Value', dest_val);
        
    else
        errordlg( [dest_str{ dest_val}, ' already exists. Choose a different label.'], 'Label conflication');
    end
end
handles.userdata.roiname = get( handles.label_list, 'String');
guidata( hObject, handles);

% --- Executes on button press in preview_label.
function preview_label_Callback(hObject, eventdata, handles)
% hObject    handle to preview_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
[clust_ind_in_raw] = PlaceLabel( handles);
if ~isempty( clust_ind_in_raw)
    guidata( hObject, handles);
    redraw( handles, clust_ind_in_raw);
end

function threshold_percent_Callback(hObject, eventdata, handles)
% hObject    handle to threshold_percent (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of threshold_percent as text
%        str2double(get(hObject,'String')) returns contents of threshold_percent as a double
val = str2double( get( hObject, 'String'));
if isscalar( val) || ~isnan( val)    
    handles.elec.threshold_perecent = val;
    guidata( hObject, handles);
    preview_label_Callback( handles.preview_label, [], handles);
end
redraw( handles);


% --- Executes during object creation, after setting all properties.
function threshold_percent_CreateFcn(hObject, eventdata, handles)
% hObject    handle to threshold_percent (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes during object deletion, before destroying properties.
function figure1_DeleteFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on key press with focus on figure1 or any of its controls.
function figure1_WindowKeyPressFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  structure with the following fields (see MATLAB.UI.FIGURE)
%	Key: name of the key that was pressed, in lower case
%	Character: character interpretation of the key(s) that was pressed
%	Modifier: name(s) of the modifier key(s) (i.e., control, shift) pressed
% handles    structure with handles and user data (see GUIDATA)

if ~isfield( handles, 'mri')
    return;
end

% current object
obj = get( hObject, 'CurrentObject');
tag = get( obj, 'tag');

% track label listbox
label_changed = 'no';

switch lower( eventdata.Key)
    case {'uparrow', 'downarrow', 'leftarrow', 'rightarrow'}
        % navigation keys
        do_draw = 'yes';
        if ~isempty( tag)            
            switch tag
                case 'img_coordx'
                    if strcmpi( eventdata.Key, 'uparrow')
                        handles.mriinfo.i = min( [handles.mriinfo.i + 1, handles.dims(1)]);
                    elseif strcmpi( eventdata.Key, 'downarrow')
                        handles.mriinfo.i = max( [handles.mriinfo.i - 1, 1]);
                    else
                        % do nothing
                    end

                case 'img_coordy'
                    if strcmpi( eventdata.Key, 'uparrow')
                        handles.mriinfo.j = min( [handles.mriinfo.j + 1, handles.dims(2)]);
                    elseif strcmpi( eventdata.Key, 'downarrow')
                        handles.mriinfo.j = max( [handles.mriinfo.j - 1, 1]);
                    else
                        % do nothing
                    end

                case 'img_coordz'
                    if strcmpi( eventdata.Key, 'uparrow')
                        handles.mriinfo.k = min( [handles.mriinfo.k + 1, handles.dims(3)]);
                    elseif strcmpi( eventdata.Key, 'downarrow')
                        handles.mriinfo.k = max( [handles.mriinfo.k - 1, 1]);
                    else
                        % do nothing
                    end

                case {'lh_transp', 'rh_transp', 'label_list', 'label_in_parc'}
                    % any focused object when redraw is not needed
                    do_draw = 'no';
                    
                otherwise
                    % move labels
                    val = get( handles.label_list, 'Value');
                    str = get( handles.label_list, 'String');
                    if ~isempty( str)
                        if strcmpi( eventdata.Key, 'uparrow')
                            if val > 1
                                label_changed = 'yes';
                                val = val - 1;
                            end

                        elseif strcmpi( eventdata.Key, 'downarrow')
                            if val < length( str)
                                label_changed = 'yes';
                                val = val + 1;
                            end
                        else
                            % do nothing
                        end
                        set( handles.label_list, 'Value', val);
                    end                    
            end % focus on object

        else
            % current axes was set
            if ~isempty( handles.last_click_ax)
                if handles.last_click_ax == 1
                    % move along y&z direction
                    if strcmpi( eventdata.Key, 'uparrow')
                        handles.mriinfo.k = min( [handles.mriinfo.k + 1, handles.dims(3)]);

                    elseif strcmpi( eventdata.Key, 'downarrow')
                        handles.mriinfo.k = max( [handles.mriinfo.k - 1, 1]);

                    elseif strcmpi( eventdata.Key, 'leftarrow')
                        handles.mriinfo.j = max( [1, handles.mriinfo.j-1]);

                    elseif strcmpi( eventdata.Key, 'rightarrow')
                        handles.mriinfo.j = min( [handles.mriinfo.j + 1, handles.dims(2)]);

                    else
                        % do nothing
                    end

                elseif handles.last_click_ax == 2
                    % move along x&z direction
                    if strcmpi( eventdata.Key, 'uparrow')
                        handles.mriinfo.k = min( [handles.mriinfo.k + 1, handles.dims(3)]);

                    elseif strcmpi( eventdata.Key, 'downarrow')
                        handles.mriinfo.k = max( [handles.mriinfo.k - 1, 1]);

                    elseif strcmpi( eventdata.Key, 'leftarrow')
                        handles.mriinfo.i = max( [1, handles.mriinfo.i-1]);

                    elseif strcmpi( eventdata.Key, 'rightarrow')
                        handles.mriinfo.i = min( [handles.mriinfo.i + 1, handles.dims(1)]);

                    else
                        % do nothing
                    end

                else
                    % move along x&y direction
                    if strcmpi( eventdata.Key, 'uparrow')
                        handles.mriinfo.j = min( [handles.mriinfo.j + 1, handles.dims(2)]);

                    elseif strcmpi( eventdata.Key, 'downarrow')
                        handles.mriinfo.j = max( [handles.mriinfo.j - 1, 1]);

                    elseif strcmpi( eventdata.Key, 'leftarrow')
                        handles.mriinfo.i = max( [1, handles.mriinfo.i-1]);

                    elseif strcmpi( eventdata.Key, 'rightarrow')
                        handles.mriinfo.i = min( [handles.mriinfo.i + 1, handles.dims(1)]);

                    else
                        % do nothing
                    end

                end
            end % the last click was within one of the axeses
        end % focus is on edit box
        
        tmp = handles.mri.vox2ras1 * [handles.mriinfo.i; handles.mriinfo.j; handles.mriinfo.k; 1];
        handles.mriinfo.std_coord = tmp(1:3);
        guidata( hObject, handles);
        if strcmpi( do_draw, 'yes')  
            if strcmpi( label_changed, 'yes')
                % this callback function does the redraw
                label_list_Callback( handles.label_list, [], handles);
            else
                redraw( handles);
            end
        end

    case 'a'        
        % add label
        if isempty( tag) || strcmpi( tag, 'figure1')
            add_label_Callback( handles.add_label, [], handles);
        end
        
    case 'r'
        % remove label
        if isempty( tag) || strcmpi( tag, 'figure1') || strcmpi( tag, 'label_list') 
            remove_label_Callback( handles.add_label, [], handles);
        end
        
    case 'n'
        % rename current selected label
        if isempty( tag) || strcmpi( tag, 'figure1') || strcmpi( tag, 'label_list')
                val = get( handles.label_list, 'Value');
                if val > 0
                    str = inputdlg( 'Enter new label: ', 'Rename Label');
                    % str = inputdlg( 'Enter new label: ', 'Rename Label', 1, handles.label_list.String{val});            
                    if ~isempty( str)
                        set( handles.label_name, 'String', str{1});
                        new_name_Callback( handles.new_name, [], handles);
                    end
                end
        end
        
    case 'comma'
         % assign label
        if isempty( tag) || strcmpi( tag, 'figure1')  ||  strcmpi( tag, 'label_list')    || strcmpi( tag, 'dest_label')   
            rename_label_Callback( handles.rename_label, [], handles);
        end
        
    case 'q'
        % quit
        if strcmpi( handles.gui_mode, 'interactive')
            uiresume( handles.figure1);
        end
        
    otherwise
        if strcmpi( eventdata.Modifier, 'control')
            if strcmpi( eventdata.Key, 'l')
                menu_load_label_Callback( handles.menu_load_label, [], handles);
            end
        end
        
end % key switch

% --- Executes on key release with focus on figure1 or any of its controls.
function figure1_WindowKeyReleaseFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  structure with the following fields (see MATLAB.UI.FIGURE)
%	Key: name of the key that was released, in lower case
%	Character: character interpretation of the key(s) that was released
%	Modifier: name(s) of the modifier key(s) (i.e., control, shift) released
% handles    structure with handles and user data (see GUIDATA)

% --- Executes on key press with focus on img_coordx and none of its controls.
function img_coordx_KeyPressFcn(hObject, eventdata, handles)
% hObject    handle to img_coordx (see GCBO)
% eventdata  structure with the following fields (see MATLAB.UI.CONTROL.UICONTROL)
%	Key: name of the key that was pressed, in lower case
%	Character: character interpretation of the key(s) that was pressed
%	Modifier: name(s) of the modifier key(s) (i.e., control, shift) pressed
% handles    structure with handles and user data (see GUIDATA)

function threshold_Callback(hObject, eventdata, handles)
% hObject    handle to threshold (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of threshold as text
%        str2double(get(hObject,'String')) returns contents of threshold as a double
val = str2double( get( hObject, 'String'));
if isscalar( val) || ~isnan( val)    
    handles.elec.threshold = val;
    guidata( hObject, handles);
    preview_label_Callback( handles.preview_label, [], handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function threshold_CreateFcn(hObject, eventdata, handles)
% hObject    handle to threshold (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function radius_Callback(hObject, eventdata, handles)
% hObject    handle to radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of radius as text
%        str2double(get(hObject,'String')) returns contents of radius as a double
val = str2double( get( hObject, 'String'));
if isscalar( val) || ~isnan( val)    
    handles.elec.radius = val;
    guidata( hObject, handles);
    preview_label_Callback( handles.preview_label, [], handles);
end
redraw( handles);

% --- Executes during object creation, after setting all properties.
function radius_CreateFcn(hObject, eventdata, handles)
% hObject    handle to radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in load_label.
function load_label_Callback(hObject, eventdata, handles)
% hObject    handle to load_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

[filename, p] = uigetfile( '*.txt', 'Select label file');
if filename == 0
    return;
end
labels = ReadLabel( fullfile( p, filename));
if ~isempty( labels)
    set( handles.dest_label, 'String', labels, 'Value', 1);
    guidata( hObject, handles);
end

    function h = UpdateXYLims( handles)
    % move current pointer postion to center if it's out of view
        i = handles.mriinfo.i;
        j = handles.mriinfo.j;
        k = handles.mriinfo.k;    
        for ax_idx = 1 : 3
            cur_ax = handles.userdata.ax( ax_idx);
            xlim = cur_ax.xlim;
            ylim = cur_ax.ylim;

            if ax_idx == 1
                xlim = CenterLim( xlim, j);
                ylim = CenterLim( ylim, k);
            elseif ax_idx == 2
                xlim = CenterLim( xlim, i);
                ylim = CenterLim( ylim, k);
            else
                xlim = CenterLim( xlim, i);
                ylim = CenterLim( ylim, j);
            end        
            handles.userdata.ax( ax_idx).xlim = xlim;
            handles.userdata.ax( ax_idx).ylim = ylim;        
        end
        h = handles.userdata.ax;
        guidata( handles.figure1, handles);

     function lim = CenterLim( lim, loc)
         d = diff( lim);
         if loc < lim(1) || loc > lim( 2)
             lim = loc + 0.5*d*[-1, 1];
         end


% --- Executes on button press in use_peak.
function use_peak_Callback(hObject, eventdata, handles)
% hObject    handle to use_peak (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of use_peak
if get( hObject, 'Value') == 1
    handles.elec.use_peak = 'yes';
else
    handles.elec.use_peak = 'no';
end
guidata( hObject, handles);


% --- Executes on selection change in peak_type.
function peak_type_Callback(hObject, eventdata, handles)
% hObject    handle to peak_type (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns peak_type contents as cell array
%        contents{get(hObject,'Value')} returns selected item from peak_type
str = get( hObject, 'String');
handles.elec.peak_type = str( get( hObject, 'Value'));
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function peak_type_CreateFcn(hObject, eventdata, handles)
% hObject    handle to peak_type (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in initial_center.
function initial_center_Callback(hObject, eventdata, handles)
% hObject    handle to initial_center (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of initial_center
if get( hObject, 'Value') == 1
   handles.elec.initial_center = 'yes';
   set( [handles.initial_center_threshold, handles.center_radius], 'enable', 'on');
else
    handles.elec.initial_center = 'no';
    set( [handles.initial_center_threshold, handles.center_radius], 'enable', 'off');
end

set( [handles.initial_center_threshold, handles.center_radius], 'backgroundcolor', [1 0 0]);
set( [handles.initial_center_threshold, handles.center_radius], 'backgroundcolor', [0 0 0]);       
guidata( hObject, handles);


function center_radius_Callback(hObject, eventdata, handles)
% hObject    handle to center_radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of center_radius as text
%        str2double(get(hObject,'String')) returns contents of center_radius as a double
orig_val = handles.elec.center_radius;
val = str2double( get( hObject, 'String'));
if isscalar( val) && ~isnan( val) && val > 0 
    handles.elec.center_radius = val;
else
    set( hObject, 'String', num2str( orig_val));
end
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function center_radius_CreateFcn(hObject, eventdata, handles)
% hObject    handle to center_radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function clust_radius_Callback(hObject, eventdata, handles)
% hObject    handle to clust_radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of clust_radius as text
%        str2double(get(hObject,'String')) returns contents of clust_radius as a double
orig_val = handles.elec.clust_radius;
val = str2double( get( hObject, 'String'));
if isscalar( val) && ~isnan( val) && val > 0 
    handles.elec.clust_radius = val;
else
    set( hObject, 'String', num2str( orig_val));
end
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function clust_radius_CreateFcn(hObject, eventdata, handles)
% hObject    handle to clust_radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function overlap_threshold_Callback(hObject, eventdata, handles)
% hObject    handle to overlap_threshold (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of overlap_threshold as text
%        str2double(get(hObject,'String')) returns contents of overlap_threshold as a double
orig_val = handles.elec.overlap_threshold;
val = str2double( get( hObject, 'String'));
if isscalar( val) && ~isnan( val) && val >= 0 % && val < 1
    % if val is greater than 1, this absolute value will be used
    handles.elec.overlap_threshold = val;
else
    set( hObject, 'String', num2str( orig_val));
end
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function overlap_threshold_CreateFcn(hObject, eventdata, handles)
% hObject    handle to overlap_threshold (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function sigma_Callback(hObject, eventdata, handles)
% hObject    handle to sigma (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of sigma as text
%        str2double(get(hObject,'String')) returns contents of sigma as a double
orig_val = handles.elec.sigma;
val = str2double( get( hObject, 'String'));
if isscalar( val) && ~isnan( val) && val > 0 
    handles.elec.sigma = val;
else
    set( hObject, 'String', num2str( orig_val));
end
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function sigma_CreateFcn(hObject, eventdata, handles)
% hObject    handle to sigma (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function peak_radius_Callback(hObject, eventdata, handles)
% hObject    handle to peak_radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of peak_radius as text
%        str2double(get(hObject,'String')) returns contents of peak_radius as a double
orig_val = handles.elec.peak_radius;
val = str2double( get( hObject, 'String'));
if isscalar( val) && ~isnan( val) && val > 0 
    handles.elec.peak_radius = val;
else
    set( hObject, 'String', num2str( orig_val));
end
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function peak_radius_CreateFcn(hObject, eventdata, handles)
% hObject    handle to peak_radius (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

    function c = UpdateYokeCoord( dims, trans, rois)
        [X, Y, Z] = ndgrid( 1:dims(1), 1:dims(2), 1:dims(3));
        X = X(:);
        Y = Y(:);
        Z = Z(:);
        c = zeros( length( rois), 3);    
        for roi_idx = 1 : length( rois)
            roi_ind = rois{ roi_idx};       
            % unweighted center
            tmp = round( mean( [X( roi_ind), Y( roi_ind), Z( roi_ind)], 1));
            c_img = trans * [tmp(:); 1];
            c( roi_idx, :) = c_img( 1:3);
        end

% --- Executes on button press in use_exact.
function use_exact_Callback(hObject, eventdata, handles)
% hObject    handle to use_exact (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of use_exact
handles = PlaceLabelOptsSetup( handles);
guidata( hObject, handles);

% --- Executes on button press in find_peak.
function find_peak_Callback(hObject, eventdata, handles)
% hObject    handle to find_peak (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of find_peak
handles = PlaceLabelOptsSetup( handles);
guidata( hObject, handles);

function initial_center_threshold_Callback(hObject, eventdata, handles)
% hObject    handle to initial_center_threshold (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of initial_center_threshold as text
%        str2double(get(hObject,'String')) returns contents of initial_center_threshold as a double
val = str2double( get( hObject, 'String'));
orig_val = handles.initial_center_threshold;
if isscalar( val) && ~isnan( val) && val >= 0 && val <=1
    handles.elec.center_threshold = val;
else
    set( handles.initial_center_threshold, 'String', num2str( orig_val));
end
guidata( hObject, handles);

% --- Executes during object creation, after setting all properties.
function initial_center_threshold_CreateFcn(hObject, eventdata, handles)
% hObject    handle to initial_center_threshold (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

    % whether a point is whithin a rectangle
    function in_pnt = within_range( rng, pnt)
        %   rng, [x_lo, x_hi, y_lo, y_hi]
        %   pnt, (x, y)
        in_pnt = 'no';
        if pnt(1) >= min( rng(1:2)) && pnt(1) <= max( rng(1:2)) && pnt(2) >= min( rng(3:4)) && pnt(2) <= max( rng(3:4))
            in_pnt = 'yes';
        end

% --- Executes on button press in use_hand_roi.
function use_hand_roi_Callback(hObject, eventdata, handles)
% hObject    handle to use_hand_roi (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of use_hand_roi
handles = PlaceLabelOptsSetup( handles);
guidata( hObject, handles);

% --------------------------------------------------------------------
function help_Callback(hObject, eventdata, handles)
% hObject    handle to help (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

if isfield( handles, 'mri')
    fprintf( ['Source image: ', handles.src_img, '\n']);
else
    fprintf( ['Source image has not been set.\n']);
end

% --------------------------------------------------------------------
function close_fig_Callback(hObject, eventdata, handles)
% hObject    handle to close_fig (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
figure1_CloseRequestFcn( handles.figure1, [], handles);

% --- Executes on mouse press over figure background.
function figure1_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

function label_name_Callback(hObject, eventdata, handles)
% hObject    handle to label_name (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of label_name as text
%        str2double(get(hObject,'String')) returns contents of label_name as a double

% --- Executes during object creation, after setting all properties.
function label_name_CreateFcn(hObject, eventdata, handles)
% hObject    handle to label_name (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in new_name.
function new_name_Callback(hObject, eventdata, handles)
% hObject    handle to new_name (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
str = get( handles.label_name, 'String');
if ~isempty( str)
    val = get( handles.label_list, 'Value');
    if ~isempty( val) && length( val) == 1
        handles.userdata.roiname{ val} = str;  
        labels = get( handles.label_list, 'String');
        str_loc = LabelLocation( labels, str);
        
        if ~isempty( str_loc) && ~strcmpi( labels( val), str)
            fprintf( 'Label name already exists\n');
            h = errordlg( 'Label name already exists', 'Label name conflict.');
            pause( 3);
            if isvalid( h)
                close( h);
            end            
        else
            labels{ val} = str;
            set( handles.label_list, 'String', labels, 'Value', val);
            guidata( hObject, handles);
        end
    end    
end

    % options for electrode placement
    function handles = PlaceLabelOptsSetup( handles)
        % disable all               
        set( [handles.use_peak,...
            handles.peak_type,...
            handles.peak_radius,...
            handles.initial_center,...
            handles.center_radius,...
            handles.initial_center_threshold,...
            handles.overlap_threshold,...
            handles.find_peak,...
            handles.clust_radius,...
            handles.sigma,...
            handles.use_exact,...
            handles.use_hand_roi], 'enable', 'off');
        
        if get( handles.use_exact, 'Value') == 1
            % use exactly cursor location
            % disable all other optioins
            set( handles.use_exact, 'enable', 'on');
            
        elseif get( handles.find_peak, 'Value') == 1
            % disable all except peak_type and peak_radius
            set( [handles.peak_type, handles.peak_radius, handles.find_peak], 'enable', 'on');
            
        elseif get( handles.use_hand_roi, 'Value') == 1
            % disable all except overlap_threshold
            set( [handles.overlap_threshold,...
                handles.use_hand_roi], 'enable', 'on');
        else 
            % enable all
            set( [handles.use_peak,...
                handles.peak_type,...
                handles.peak_radius,...
                handles.initial_center,...
                handles.center_radius,...
                handles.initial_center_threshold,...
                handles.overlap_threshold,...
                handles.find_peak,...
                handles.clust_radius,...
                handles.sigma,...
                handles.use_exact,...
                handles.use_hand_roi], 'enable', 'on');
            
            if get( handles.initial_center, 'Value') == 0
                set( handles.initial_center_threshold, 'enable', 'off');
                set( handles.center_radius, 'enable', 'off');            
            end
        end
        
        set( [handles.peak_radius,...
            handles.center_radius,...
            handles.initial_center_threshold,...
            handles.overlap_threshold,...
            handles.clust_radius,...
            handles.sigma], 'backgroundcolor', [1 0 0]);

        set( [handles.peak_radius,...
            handles.center_radius,...
            handles.initial_center_threshold,...
            handles.overlap_threshold,...
            handles.clust_radius,...
            handles.sigma], 'backgroundcolor', [1, 1, 1] * 0.2);


% --- Executes on key release with focus on figure1 and none of its controls.
function figure1_KeyReleaseFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  structure with the following fields (see MATLAB.UI.FIGURE)
%	Key: name of the key that was released, in lower case
%	Character: character interpretation of the key(s) that was released
%	Modifier: name(s) of the modifier key(s) (i.e., control, shift) released
% handles    structure with handles and user data (see GUIDATA)


% --- Executes when user attempts to close figure1.
function figure1_CloseRequestFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: delete(hObject) closes the figure
% delete(hObject);
% close_fig_Callback( handles.close_fig, [], handles);

if isfield( handles, 'mri')
    if ~isempty( handles.userdata.rois)
        if isfield( handles, 'results_saved') && strcmpi( handles.results_saved, 'no')
            % make sure results were saved
            response = questdlg( 'Quit without saving results?', '', 'Yes', 'No', 'No');
            if strcmpi( response, 'no')
                return;
            end
        end
    end
end

if strcmpi( handles.gui_mode, 'interactive')
    uiresume( handles.figure1);  
    
else
    delete( handles.figure1);    
    if isfield( handles, 'yoke')
        if isvalid( handles.yoke)
            close( get( handles.yoke, 'Parent'))
        end
    end
end

% --- Executes on button press in draw_mask.
function draw_mask_Callback(hObject, eventdata, handles)
% hObject    handle to draw_mask (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of draw_mask
if get( hObject, 'Value') == 1
    handles.draw.status = 'on';
else
    handles.draw.status = 'off';
end
guidata( hObject, handles);

function pen_val_Callback(hObject, eventdata, handles)
% hObject    handle to pen_val (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of pen_val as text
%        str2double(get(hObject,'String')) returns contents of pen_val as a double
orig_val = handles.draw.penval;
val = str2double( get( hObject, 'String'));
if isscalar( val) && ~isnan( val) && round( val) >= 0 && val <= 2000
    val = round( val);
    handles.draw.penval = val;
    nbcs = size( handles.draw.colormap, 1);
    if val > nbcs
        handles.draw.colormap = cat( 1, handles.draw.colormap, rand( val-nbcs, 3));
    end
else
    hObject.String = num2str( orig_val);
end
guidata( hObject, handles);
redraw( handles);

% --- Executes during object creation, after setting all properties.
function pen_val_CreateFcn(hObject, eventdata, handles)
% hObject    handle to pen_val (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function pen_sz_Callback(hObject, eventdata, handles)
% hObject    handle to pen_sz (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of pen_sz as text
%        str2double(get(hObject,'String')) returns contents of pen_sz as a double

% --- Executes during object creation, after setting all properties.
function pen_sz_CreateFcn(hObject, eventdata, handles)
% hObject    handle to pen_sz (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --------------------------------------------------------------------
function load_elect_Callback(hObject, eventdata, handles)
% hObject    handle to load_elect (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
[filename, p] = uigetfile( '*.mat', 'Select existing elecrode file');
if filename == 0
    return;
end

elec = fullfile( p, filename);
elec = load( elec);
if ~isfield( elec, 'elec')
    warndlg( 'Electrode file was probably not generated by this program');
    
else
    elec = elec.elec;
    % electrodes
    handles.userdata.roiname = elec.label;
    handles.userdata.rois = elec.rois;    
    try
        handles.userdata.reg = elec.reg;
        handles.userdata.elec_proj = elec.proj;
        handles.userdata.atlas = elec.atlas;
    catch
        % do nothing
    end
    
    set( handles.label_list, 'String', handles.userdata.roiname,...
        'Value', min( [length( handles.userdata.roiname), 1]));
    set( handles.coord_space_name, 'String', ['Loading electrodes :' fullfile( p, filename)]);
    drawnow;
    
    [cmat, ctable] = ColorTable( handles.userdata.rois, handles.dims);
    handles.cmat = cmat;
    handles.c = ctable;
   
    % update existing yoke fiugre
    handles = InitializeYoke( handles);    
    set( handles.show_yoke, 'Value', 1);
    handles.userdata.yoke_coord = UpdateYokeCoord( handles.dims, handles.mri.vox2ras1, handles.userdata.rois);
    guidata( hObject, handles); 
end

% --- Executes during object creation, after setting all properties.
function draw_mask_CreateFcn(hObject, eventdata, handles)
% hObject    handle to draw_mask (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% --- Executes during object creation, after setting all properties.
function figure1_CreateFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% --------------------------------------------------------------------
function load_elec_mask_Callback(hObject, eventdata, handles, varargin)
% hObject    handle to load_elec_mask (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% auto cluster folders

% varagin{1}, directory to auto masks
if nargin > 3
    roi = G_GetFiles( varargin{1}, '', 'nii.gz', 0);
    p = varargin{1};
    
else
    [roi, p] = uigetfile( '*.nii.gz', 'Select mask files', 'multiselect', 'on');
end

if iscell( roi)
    % nth
elseif ischar( roi)
    roi = {roi};
elseif roi==0
    roi = {};
else
    % nth
end

if ~isempty( roi)
    % read labels
    nbrois = length( roi);  
    roi_inds = cell( nbrois, 1);
    ind = ones( nbrois, 1);
    for roi_idx = 1 : nbrois
        roiimg = MRIread( fullfile( p, roi{ roi_idx}));
        set( handles.coord_space_name, 'String', ['Loading labels ', num2str( roi_idx), '/', num2str(nbrois)]);
        drawnow;
        sz = size( roiimg.vol);
        if ~all( sz( [2 1 3]) == handles.dims) || size( roiimg.vol, 4) ~= 1
            set( handles.coord_space_name, 'String',...
                ['Dimension of ', roi{ roi_idx}, ' does not match main input, skipped']);
            drawnow;
            ind( roi_idx) = 0;
            continue;
        end
        roiimg.vol = permute( roiimg.vol, [2 1 3 4]);
        roi_inds{ roi_idx} = find( roiimg.vol( :) > 0);
    end
    roi_inds( ind==0) = [];
    
    set( handles.coord_space_name, 'String', '');
    drawnow;
            
    % update label listbox
    if ~isempty( roi_inds)        
        roi( ind==0) = [];
        nbrois = length( roi);
        % label list
        N = length( handles.userdata.roiname);
        handles.userdata.roiname( N+1 : N+nbrois) = roi;
        set( handles.label_list,...
            'String', handles.userdata.roiname,...
            'Value', length( handles.userdata.roiname));

        handles.userdata.rois( N+1 : N+nbrois) = roi_inds;    

        % color for each label
        [cmat, ctable] = ColorTable( handles.userdata.rois, handles.dims);
        handles.cmat = cmat;
        handles.c = ctable;

        handles.userdata.yoke_coord = UpdateYokeCoord( handles.dims, handles.mri.vox2ras1, handles.userdata.rois);
        guidata( hObject, handles);
        redraw( handles);
    end 
end       
  
% --- Executes on button press in show_atlas.
function show_atlas_Callback(hObject, eventdata, handles)
% hObject    handle to show_atlas (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of show_atlas
if get( hObject, 'Value') == 1
    handles.userdata.show_atlas = 'yes';
    set( handles.atlas, 'visible', 'on');
else
    handles.userdata.show_atlas = 'no';
    set( handles.atlas, 'String', '', 'visible', 'off');
end
set( hObject, 'backgroundcolor', [1 0 0]);
set( hObject, 'backgroundcolor', [0 0 0]);
guidata( hObject, handles);
redraw( handles);

% --- Executes during object creation, after setting all properties.
function std_img_CreateFcn(hObject, eventdata, handles)
% hObject    handle to std_img (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes during object creation, after setting all properties.
function transmat_txt_CreateFcn(hObject, eventdata, handles)
% hObject    handle to transmat_txt (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
set( hObject, 'String', '');
guidata( hObject, handles);

% --- Executes on slider movement.
function elec_transp_Callback(hObject, eventdata, handles)
% hObject    handle to elec_transp (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'Value') returns position of slider
%        get(hObject,'Min') and get(hObject,'Max') to determine range of slider
handles.elec.elec_transp = get( hObject, 'Value');
guidata( hObject, handles);
redraw( handles);

% --- Executes during object creation, after setting all properties.
function elec_transp_CreateFcn(hObject, eventdata, handles)
% hObject    handle to elec_transp (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: slider controls usually have a light gray background.
if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor',[.9 .9 .9]);
end
set( hObject, 'Value', 1);
guidata( hObject, handles);

% --- Executes on button press in sort_label_list.
function sort_label_list_Callback(hObject, eventdata, handles)
% hObject    handle to sort_label_list (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if ~isempty( handles.userdata.roiname)
    % current location in label_list    
    [new_str, new_str_idx] = SortStr( handles.userdata.roiname);
    handles.userdata.roiname = new_str;
    set( handles.label_list, 'String', new_str, 'Value', 1);
    handles.userdata.rois = handles.userdata.rois( new_str_idx);
    handles.userdata.yoke_coord = UpdateYokeCoord( handles.dims, handles.mri.vox2ras1, handles.userdata.rois);
    
    guidata( hObject, handles);
    redraw( handles);
    label_list_Callback( handles.label_list, [], handles);
end

function Untitled_1_Callback(hObject, eventdata, handles)
% hObject    handle to Untitled_1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% --------------------------------------------------------------------
function menu_load_label_Callback(hObject, eventdata, handles)
% hObject    handle to menu_load_label (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
[filename, p] = uigetfile( '*.txt', 'Select label file');
if filename == 0
    return;
end

set( [handles.dest_label, handles.real_label_text, handles.rename_label],...
    'enable', 'on', 'visible', 'on');
labels = ReadLabel( fullfile( p, filename));
if ~isempty( labels)
    set( handles.dest_label,...
        'String', labels, 'Value', 1);
    guidata( hObject, handles);
end   

% --- Executes on button press in show_yoke.
function show_yoke_Callback(hObject, eventdata, handles)
% hObject    handle to show_yoke (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of show_yoke
if get(hObject,'Value') == 1
    handles = InitializeYoke( handles);
else
    if isfield( handles, 'yoke') && isvalid( handles.yoke)
        close( handles.yoke.Parent)
    end
end
guidata( hObject, handles);
redraw( handles);

    function labels = ReadLabel( filename)
        try
            labels = importdata( filename);
        catch
            labels = {};
        end
