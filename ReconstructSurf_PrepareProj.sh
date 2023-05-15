#!/usr/bin/env bash
#
# Prepare Freesurfer files for projecting grid electrodes to brain surface
#
# Matlab is required.
#
# 1. Raw anatomical image: T1.nii.gz
#
# 2. Then perform freesurfer reconstruction using T1.nii.gz (let's call this space FSL_Space)
#       e.g.: recon-all -i T1.nii.gz -subjid ${subjid} -no-isrunning
#       details of how to run the rest of the reconstruction is dicusses somewhere else
#   tkmedit your_subject_name brainmask.mgz -aux T1.mgz
#   tkmedit your_subject_name brainmask.mgz -aux wm.mgz -surfs
#   tkmedit your_subject_name brainmask.mgz -surfs -aseg
#
# 3. After the cortical reconstruction is done with Freesufer
#    there will be a rawavg.nii.gz and orig.nii.gz in the folder mri
#    where rawavg.nii.gz is in the same space to T1.nii.gz and orig.nii.gz is in Freesurfer space (Freesurface_Space)
#    let say *.pial.* are in Freesurfer_Surface_Space
# With those terms of spaces in mind, it would probably be easier to under the example Matlab code Coordinates.m
#   

# Freesurfer's surf directory, in-full-path
# e.g. surf_dir=~/Desktop/Data/ECoG/Electrodes/JP/FS/surf
surf_dir=$1

# se_diameter is the diameter of the sphere (in mm), use 15mm by default to close the sulci. See Freesurfer's make_outer_surface Matlab function
# default 15 (in millimeter), increase this number if the resulting hull is not smooth enough
se_diameter=15

# 0, yes; 1, no.
do_surf_smooth=0

# rerun 1 - no; 0 - yes.
rerun=0


hipp_hbt=hippoAmygLabels-T1.v22.HBT.FSvoxelSpace
hipp_ca=hippoAmygLabels-T1.v22.CA.FSvoxelSpace

#export FREESURFER_HOME=~/Desktop/Toolbox/freesurfer
export DYLD_FALLBACK_LIBRARY_PATH=/Applications/freesurfer/tktools
export DYLD_LIBRARY_PATH=
source $FREESURFER_HOME/SetUpFreeSurfer.sh

# If Freesurfer is installed on our computer, no need to change this.
# Otherwise replace '${FREESURFER_HOME}/matlab' with the directory to the matlab toolbox you downloaded somewhere else
fs_matlab=${FREESURFER_HOME}/matlab

###############################################################################################################################################
[[ -d "$surf_dir" ]] || { printf "${surf_dir} does not exist.\n"; exit 1; }
[[ -d "${fs_matlab}" ]] || { printf "${fs_matlab} does not exist.\n"; exit 1; }

# generate cortex hull for projection
# Use Freesurfer
#   recon-all -s $subj -localGI
# Use fieldtrip
#%   cfg             = [];
#%   cfg.method      = 'cortexhull';
#%   cfg.headshape   = '~/surf/lh.pial';
#%   cortex_hull     = ft_prepare_mesh( cfg);
d=$( dirname ${surf_dir} )
n=$( basename ${surf_dir} )
surf_dir=${d}/${n}
d=$( dirname ${fs_matlab} )
n=$( basename ${fs_matlab} )
fs_matlab=${d}/${n}

tmp_dir=${surf_dir}/tmp
[ -d ${tmp_dir} ] || mkdir ${tmp_dir}

###############################################################################################################################################
# registration between native space (FSL_Space) and Freesurfer_Space
# four new files will be generated in Freesufer's mri folder: rawavg.nii.gz, orig.nii.gz, raw2orig.mat, and orig2raw.mat
# raw2orig.mat and orig2raw.mat are transfomation matrices that can be used by FSL's flirt
subjdir=$( dirname ${surf_dir})
mridir=${subjdir}/mri
subjid=$( basename ${subjdir})
export SUBJECTS_DIR=$( dirname ${subjdir})

orig_path=$(pwd)

if [[ -f ${mridir}/raw2orig.mat && $rerun -eq 1  ]]; then
    printf "Transformation matrix from native space to freesurfer space already exists.\n"

else
    printf "Creating transformation matrix from native space to freesurfer space\n"
    cd "${mridir}"

    mri_convert rawavg.mgz rawavg.nii.gz
    mri_convert orig.mgz orig.nii.gz

    flirt -in rawavg.nii.gz -ref orig.nii.gz -dof 6 -omat raw2orig.mat
    convert_xfm -omat orig2raw.mat -inverse raw2orig.mat

    # CRS (Voxel) in orig.mgz -> surface coordinates
    mri_info --vox2ras-tkr orig.mgz > Torig.txt

    # mgz -> nifti
    for vol in orig brainmask brain; do
        oimg=${vol}-in-rawavg
        mri_vol2vol --mov ${vol}.mgz --targ rawavg.mgz --regheader --o ${oimg}.mgz --no-save-reg
        mri_convert ${oimg}.mgz ${oimg}.nii.gz
    done

    if [[ -f ${mridir}/aseg.mgz ]]; then
        mri_label2vol --seg aseg.mgz --temp rawavg.mgz --o aseg-in-rawavg.mgz --regheader aseg.mgz
        mri_convert aseg-in-rawavg.mgz aseg-in-rawavg.nii.gz
    fi

    if [[  -f ${mridir}/aparc.a2009s+aseg.mgz  ]]; then
        mri_label2vol --seg aparc.a2009s+aseg.mgz --temp rawavg.mgz --o aparc.a2009s+aseg-in-rawavg.mgz --regheader aseg.mgz
        mri_convert aparc.a2009s+aseg-in-rawavg.mgz aparc.a2009s+aseg-in-rawavg.nii.gz
    fi

    if [[ -f ${mridir}/aparc+aseg.mgz ]]; then
        mri_label2vol --seg aparc+aseg.mgz --temp rawavg.mgz --o aparc+aseg-in-rawavg.mgz --regheader aparc+aseg.mgz
        mri_convert aparc+aseg-in-rawavg.mgz aparc+aseg-in-rawavg.nii.gz
        flirt -in aparc+aseg-in-rawavg.nii.gz -ref orig.nii.gz -interp nearestneighbour -out aparc+aseg-in-orig.nii.gz
    fi
fi

# hippocampus and amygdala segmentation
bdir=${FREESURFER_HOME}/bin
command -v ${bdir}/segmentHA_T1.sh 1>/dev/null
if [[ $? -eq 0 ]]; then
    for atlas in ${hipp_hbt} ${hipp_ca}; do
        [ -f ${mridir}/lh.${atlas}.mgz ] && [ -f ${mridir}/rh.${atlas}.mgz ] || ${bdir}/segmentHA_T1.sh ${subjid}
        for hemi in lh rh; do
            oimg=${hemi}.${atlas}-in-rawavg
            mri_label2vol --seg ${hemi}.${atlas}.mgz --temp rawavg.mgz --o ${oimg}.mgz --regheader ${hemi}.${atlas}.mgz
            mri_convert ${oimg}.mgz ${oimg}.nii.gz
        done
    done
fi

#First, create a registration matrix between the conformed space (orig.mgz) and the native anatomical (rawavg.mgz)
reg=${mridir}/register.native.dat
[[ -f ${reg}  && ${rerun} -eq 1  ]] || tkregister2 --mov ${mridir}/rawavg.mgz --targ ${mridir}/T1.mgz --reg ${reg} --noedit --regheader

# Next, map the surface to the native space:
cd ${surfdir}
if [[ ! -f ${surfdir}/lh.pial.native || ${rerun} -eq 0  ]]; then
    if [[ -f ${subjdir}/surf/lh.pial ]]; then
        mri_surf2surf --sval-xyz pial --reg ${reg} ${mridir}/rawavg.mgz --tval lh.pial.native --tval-xyz --hemi lh --s ${subjid}
        mri_surf2surf --sval-xyz pial --reg ${reg} ${mridir}/rawavg.mgz --tval rh.pial.native --tval-xyz --hemi rh --s ${subjid}
    fi

    for ann in aparc.annot aparc.a2009s.annot; do
        mri_surf2surf --sval-annot ${ann} --reg ${reg} ${mridir}/rawavg.mgz --tval lh.${ann}.native --hemi lh --s ${subjid}
        mri_surf2surf --sval-annot ${ann} --reg ${reg} ${mridir}/rawavg.mgz --tval rh.${ann}.native --hemi rh --s ${subjid}
    done
fi

# surface smooth
if [[ ${do_surf_smooth} -eq 0 ]]; then
    command -v matlab &>/dev/null
    [ $? -eq 0 ] && { printf "Matlab was not installed.\n"; exit 1; }

    for hemi in lh rh; do
        pial_fill=${tmp_dir}/${hemi}.pial.filled.mgz
        mris_fill -c -r 1 ${surf_dir}/${hemi}.pial ${pial_fill}
        [ $? -ne 0 ] && { printf "mris_fill failed.\n"; continue; }

        pial_outer=${tmp_dir}/${hemi}.pial-outer
        matlab -nojvm -nodesktop -nosplash -r "addpath( '${fs_matlab}'); make_outer_surface( '${pial_fill}', ${se_diameter}, '${pial_outer}'); exit;";

        [ -f ${pial_outer} ] || { printf "pial smooth failed.\n"; continue; }

        mris_extract_main_component ${pial_outer} ${pial_outer}-main
        mris_smooth -nw -n 30 ${pial_outer}-main ${surf_dir}/${hemi}.pial-outer-smoothed
    done
fi

cd "$orig_path"
