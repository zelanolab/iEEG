function [coord_label, atlas_label] = AtlasQuery_HarvardOxford( coord, varargin)
% HarvardOxford Cortical- and Subcortical-atlas query
% 
% Usage
%   [coord_label] = AtlasQuery_HarvardOxford( coord);
% 
% Input
%   N x 3 MNI coordinates (in mm)
%   Optional Key-Value pairs
%       'subcort_atlas', full-path-to-HarvardOxford-sub-maxprob-thr25-1mm.nii.gz (default)
%       'cort_atlas', full-path-to-HarvardOxford-cort-maxprob-thr25-1mm.nii.gz (default)
%       'subcort_label', full-path-to-HarvardOxford-Subcortical.xml
%       'cort_label', full-path-to-HarvardOxford-Cortical.xml
%       'outfile', full-path-to-resulting-file.txt
%       'label', ''); % cell array string
%  
% Output
%   coord_label, atlas query result
% 
% naturalzhou@gmail.com
% https://sites.northwestern.edu/zelano/

options = struct( 'subcort_atlas', '',...
    'cort_atlas', '',...
    'subcort_label', '',... 
    'cort_label', '',...
    'outfile', '',...
    'label', ''); % reserved, do not change

options = G_SparseArgs( options, varargin);

sz_coord = size( coord);
if ~isempty( coord) && (length( sz_coord) ~= 2 || sz_coord( 2) ~= 3)
    error( 'Image coordinates must be given as a Nx3 matrix.');
end


subcort_atlas = options.subcort_atlas;
cort_atlas = options.cort_atlas;
subcort_label = options.subcort_label;
cort_label = options.cort_label;
if isempty( subcort_atlas) || isempty( cort_atlas) || isempty( subcort_label) || isempty( cort_label)
    fsldir = getenv( 'FSLDIR');
    if isempty( fsldir)
        error( 'FSl is not installed.');
    end
    
    d = fullfile( fsldir, 'data', 'atlases', 'HarvardOxford');
    subcort_atlas = fullfile( d, 'HarvardOxford-sub-maxprob-thr0-1mm.nii.gz');
    cort_atlas = fullfile( d, 'HarvardOxford-cort-maxprob-thr0-1mm.nii.gz');


    lbl_d = fullfile( fsldir, 'data', 'atlases');
    subcort_label = fullfile( lbl_d, 'HarvardOxford-Subcortical.xml');
    cort_label = fullfile( lbl_d, 'HarvardOxford-Cortical.xml');
end

nbcoords = sz_coord(1);
label = options.label;
if ~isempty( label)
    if ~iscell( label) || min( size( label)) ~= 1 || length( label) ~= nbcoords
        error( 'label must be a cell array with a length same to the number of coordinates.');
    end
    
else
    label = cell( nbcoords, 1);
end

atlas_label = [];
try
    subcort = MRIread( subcort_atlas);
    subcort.vol = permute( subcort.vol, [2, 1, 3]);

    cort = MRIread( cort_atlas);
    cort.vol = permute( cort.vol, [2, 1, 3]);

    [subcort_ind, subcort_label] = SparseLabel( subcort_label);
    [cort_ind, cort_label] = SparseLabel( cort_label);

    atlas_label.CorticalIndex = cort_ind;
    atlas_label.CorticalLabel = cort_label;
    atlas_label.SubcorticalIndex = subcort_ind;
    atlas_label.SubcorticalLabel = subcort_label;
    atlas_label.CortFile = cort_atlas;
    atlas_label.SubFile = subcort_atlas;

catch
    if exist( 'MRIread', 'file')
        warning( 'Atlas files were not all found');
    else
        warning( 'Freesurfer toolbox was not installed and/or not all atlas files were found.');
    end
    
    return;
end

coord_label = {};
if isempty( coord)
    return;
end

vox_c = subcort.vox2ras1 \ [coord'; ones(1, nbcoords)];
vox_c = round( vox_c( 1:3, :)');

sz = size( subcort.vol);
tmp = bsxfun( @gt, vox_c, sz);
if any( vox_c( :) < 1) || any( tmp(:))
    error( 'Invalid coordinates were found.');
end

coord_label = cell( nbcoords, 1);
for k = 1 : size( vox_c, 1)
    x = vox_c( k, 1);
    y = vox_c( k, 2);
    z = vox_c( k, 3);

    cort_name = '';    
    loc = find( abs( cort_ind - cort.vol( x, y, z)) < eps);
    if ~isempty( loc)
        cort_name = cort_label{ loc};
    end
    
    subcort_name = '';
    loc = find( abs( subcort_ind - subcort.vol( x, y, z)) < eps);
    if ~isempty( loc)
        subcort_name = subcort_label{ loc};
    end
    
    coord_label{ k, 1} = cat( 2, subcort_name, '; ', cort_name);
end

% save results to file, if specified
outfile = options.outfile;
if ~isempty( outfile)
    if exist( outfile, 'file')
        [p, name, ext] = fileparts( outfile);
        surfix = datestr( clock, 'mmmddyyyy_HH_MM');
        fprintf( [outfile, ' already exists, current time will be appended to new file.\n']);
        outfile = fullfile( p, [name, '_', surfix, ext]); 
    end
    
    fid = fopen( outfile, 'w+');
    fprintf( ['See ', outfile, ' for results\n']);
    fprintf( fid, 'Label \t MNI coordinates (x,y,z) \t atlas query results\n\r');     
    fmt = sprintf( 'Label%%0%dd', CountDigits( nbcoords));
    for k = 1 : nbcoords        
        if isempty( label)            
            lblnam = sprintf( fmt, k);
        else
            lblnam = label{ k};
        end

        s = cellstr( string( coord( k, :)));
        fprintf( fid, '%s \t (%s, %s, %s) \t %s \n\r', ...
            lblnam, s{1}, s{2}, s{3}, coord_label{ k});
    end

    fclose( fid);
end

end % main function


function [index, label] = SparseLabel( label_file)
    [~, cmdout] = system( ['cat ', label_file]);
    label_start = strfind( cmdout, '<label index="');
    label_end = strfind( cmdout, '</label>');
    nb_labels = length( label_start);
    index = zeros( nb_labels, 1);
    label = cell( nb_labels, 1);
    for k = 1 : nb_labels
        s = cmdout( label_start( k) : label_end( k));
        loc = strfind( s, '"');
        index( k) = str2double( s( loc(1)+1 : loc(2)-1)) + 1;

        loc1 = strfind( s, '>');
        loc2 = strfind( s, '<');
        label{ k} = s( loc1+1 : loc2(end)-1);
    end
end
