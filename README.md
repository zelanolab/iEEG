# iEEG
Matlab scripts for intracranial electroencephalography data analysis. 

eplace/
  eplace - GUI for electrode placement
  eviewer - GUI for electrode visualization
    
The toolbox https://github.com/HughWXY/ntools_elec is required for electrode projection to brain surface.
  
*.mlapp are the latest tools.

eplace.mlapp - Place electrode on CT image.  
enorm.mlapp - Apply the registeration transofmation to the coordinates in CT space. The transformation matrix can be created using RegCT2STD.sh.    
eviewer.mlapp - Simplified version of enorm.mlapp, which can be used for visualization purpose only.    


Jul 12, 2023. Fix bugs in eplace, and add distance measurements. Fix bugs in enorm.    
  

