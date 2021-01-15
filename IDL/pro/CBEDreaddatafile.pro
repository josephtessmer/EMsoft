;
; Copyright (c) 2013-2021, Marc De Graef Research Group/Carnegie Mellon University
; All rights reserved.
;
; Redistribution and use in source and binary forms, with or without modification, are 
; permitted provided that the following conditions are met:
;
;     - Redistributions of source code must retain the above copyright notice, this list 
;        of conditions and the following disclaimer.
;     - Redistributions in binary form must reproduce the above copyright notice, this 
;        list of conditions and the following disclaimer in the documentation and/or 
;        other materials provided with the distribution.
;     - Neither the names of Marc De Graef, Carnegie Mellon University nor the names 
;        of its contributors may be used to endorse or promote products derived from 
;        this software without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
; OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
; USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
; ###################################################################
;--------------------------------------------------------------------------
; EMsoft:CBEDreaddatafile.pro
;--------------------------------------------------------------------------
;
; PROGRAM: CBEDreaddatafile.pro
;
;> @author Marc De Graef, Carnegie Mellon University
;
;> @brief Reads the data file produced by the EMCBED.f90 program
;
;> @date 10/08/13 MDG 1.0 first attempt 
;> @date 12/06/18 MDG 2.0 conversion to HDF5 formatted input (for now only EMCBED.f90)
;--------------------------------------------------------------------------
pro CBEDreaddatafile,LACBED=LACBED,MBCBED=MBCBED
;
;------------------------------------------------------------
; common blocks
common CBED_widget_common, widget_s
common CBED_data_common, data
common PointGroups, PGTHD, PGTWD, DG

; the next common block contains all the raw data needed to generate the CBED patterns
common CBED_rawdata, gvecs, gmult, gtt, gxy, disks, numHOLZ, HOLZlist
common CBED_current, BFcurrent, DFcurrent, RGBcurrent, mask

common CommonCore, status, logmode, logunit


status = widget_s.status
logmode = 0
logunit = 10

  CBEDprint,'Reading data file '+data.dataname

; not sure if this line is really needed...
  EMdatapathname = Core_getenv(/data)

  if ( keyword_set(LACBED) ) then begin
    data.pathname = data.CBEDroot
  end else begin
    data.pathname = data.MBCBEDroot
  end

; first make sure that this is indeed an HDF file
  res = H5F_IS_HDF5(data.pathname+'/'+data.dataname)
  if (res eq 0) then begin
    Core_Print,'  This is not an HDF file ! ',/blank
    goto,skipall
  endif

; ok, so it is an HDF file; let's open it
  file_id = H5F_OPEN(data.pathname+'/'+data.dataname)
  if (file_id eq -1L) then begin
    Core_Print,'  Error opening file',/blank
    goto, skipall
  endif 

; try to open the 
  res = H5G_GET_NMEMBERS(file_id,'EMheader')
  for i=0,res[0]-1 do begin
    gname = H5G_GET_MEMBER_NAME(file_id,'EMheader',i)
    if (gname eq 'LACBED') then begin
      group_id = H5G_open(file_id,'EMheader/LACBED')
    end else begin
       H5F_close,file_id
       Core_Print,'  Could not find LACBED group in EMheader ',/blank
       goto, skipall
    endelse
  endfor

;  try to open and read the ProgramName dataset
  dset_id = H5D_open(group_id,'ProgramName')
  z = H5D_read(dset_id) 
  progname = strtrim(z[0],2)
  H5D_close,dset_id
    Core_Print,' ->File generated by program '+progname+'<-'

  if ( keyword_set(LACBED) and (progname ne 'EMLACBED.f90') ) then begin
    CBEDprint,' This file was not generated by the EMLACBED.f90 program; it is not a valid CBED file ',/blank
    H5F_close,file_id
    goto,skipall
  end

; open and read the Version dataset
  dset_id = H5D_open(group_id,'Version')
  z = H5D_read(dset_id) 
  scversion = strtrim(z[0],2)
  H5D_close,dset_id
  data.scversion = strtrim(scversion,2)
    Core_Print,'      Version identifier : '+scversion 

; close the EMheader group
  H5G_close,group_id

; ok, let's read the actual data from the file

  finfo = file_info(data.pathname+'/'+data.dataname)
  data.filesize = finfo.size
  WIDGET_CONTROL, SET_VALUE=string(float(data.filesize)/1024./1024.,FORMAT="(F8.2)")+' Mb', widget_s.filesize


; the following parameters are part of either the header group or the namelist group ... 
; progname, EMsoftversion, npix, numt, xtalname, voltage, convergence, k, fn, dmin, maxHOLZ, startthick, thickinc
  group_id = H5G_open(file_id,'EMData')

; numfam
  dset_id = H5D_open(group_id,'icnt')
  z = H5D_read(dset_id) 
  data.numfam = z[0]
  H5D_close,dset_id
  WIDGET_CONTROL, SET_VALUE=string(data.numfam,FORMAT="(I5)"), widget_s.numfam

; numk
  dset_id = H5D_open(group_id,'numk')
  z = H5D_read(dset_id) 
  data.numk = z[0]
  H5D_close,dset_id
    CBEDprint,'Number of k-vectors in disk = '+string(data.numk,FORMAT="(I)")
  WIDGET_CONTROL, SET_VALUE=string(data.numk,FORMAT="(I8)"), widget_s.numk


; first (ga) reflection
  dset_id = H5D_open(group_id,'ga')
  z = H5D_read(dset_id) 
  data.ga = z[0:2]
  H5D_close,dset_id
  wv = '('+string(data.ga[0],format="(I2)")+' '+ string(data.ga[1],format="(I2)")+' '+ string(data.ga[2],format="(I2)")+')'
    CBEDprint,'Horizontal g-vector = '+wv
  WIDGET_CONTROL, SET_VALUE=wv, widget_s.ga

; length of ga, used for proper scaling of the Laue center position
  dset_id = H5D_open(group_id,'galen')
  z = H5D_read(dset_id) 
  data.galen = z[0]
  H5D_close,dset_id

; intensity cutoff
  dset_id = H5D_open(group_id,'minten')
  z = H5D_read(dset_id) 
  data.minten = z[0]
  H5D_close,dset_id
    CBEDprint,'Intensity cutoff = '+string(data.minten,FORMAT="(E9.2)")
  WIDGET_CONTROL, SET_VALUE=string(data.minten,FORMAT="(E9.2)"), widget_s.minten

; various symmetry group numbers 
  dset_id = H5D_open(group_id,'diffgroup')
  z = H5D_read(dset_id) 
  H5D_close,dset_id
  symgroups = long(z)
  data.symgroups = symgroups
    CBEDprint,' Crystallographic point group = '+PGTHD[symgroups[0]]
    CBEDprint,' Laue PG                      = '+PGTHD[symgroups[1]]
    CBEDprint,' Diffraction PG               = '+DG[symgroups[2]]
    CBEDprint,' Projection Diff. PG          = '+DG[symgroups[3]]
    CBEDprint,' Bright Field PG              = '+PGTWD[symgroups[4]]
    CBEDprint,' Whole Pattern PG             = '+PGTWD[symgroups[5]]
    CBEDprint,' Dark Field General PG        = '+PGTWD[symgroups[6]]
    CBEDprint,' Dark Field Special PG        = '+PGTWD[symgroups[7]]
  widget_control, set_value=PGTHD[data.symgroups[0]], widget_s.symCPG
  widget_control, set_value=PGTHD[data.symgroups[1]], widget_s.symLPG
  widget_control, set_value=DG[data.symgroups[2]], widget_s.symDPG
  widget_control, set_value=DG[data.symgroups[3]], widget_s.symPDG
  widget_control, set_value=PGTWD[data.symgroups[4]], widget_s.symBFG
  widget_control, set_value=PGTWD[data.symgroups[5]], widget_s.symWPG
  widget_control, set_value=PGTWD[data.symgroups[6]], widget_s.symDFG
  widget_control, set_value=PGTWD[data.symgroups[7]], widget_s.symDFS

; initialize the Whole Pattern symmetry
  CBEDGenerate2DSymmetry,data.symgroups[5]

; read symmetry rotation angle; this is a really important parameter since it determines the 
; correct orientation of the 2D point group with respect to the diffraction disk.  We do not
; allow the user to change this, so we won't even show it.
  dset_id = H5D_open(group_id,'thetam')
  z = H5D_read(dset_id) 
  data.thetam = z[0]
  H5D_close,dset_id

  group_id = H5G_open(file_id,'NMLparameters/LACBEDNameList')

; npix
  dset_id = H5D_open(group_id,'npix')
  z = H5D_read(dset_id) 
  data.imx = 2*z[0]+1
  data.imy = 2*z[0]+1
  H5D_close,dset_id
  WIDGET_CONTROL, SET_VALUE=string(data.imx,FORMAT="(I5)"), widget_s.imx
  WIDGET_CONTROL, SET_VALUE=string(data.imy,FORMAT="(I5)"), widget_s.imy

; numt
  dset_id = H5D_open(group_id,'numthick')
  z = H5D_read(dset_id) 
  data.numt = z[0]
  H5D_close,dset_id
; WIDGET_CONTROL, SET_VALUE=string(data.numt,FORMAT="(I14)"), widget_s.numt

  data.datadims = long64( [data.imx,data.imx, data.numt, data.numfam] )
  dims = data.datadims

    CBEDprint,' data dimensions : '+string(dims[0],"(I5)")+ string(dims[1],"(I5)")+ string(dims[2],"(I5)")+ string(dims[3],"(I5)")

; create the mask
  mask = shift(dist(data.datadims[0]),data.datadims[0]/2,data.datadims[0]/2)
  mask[where (mask le data.datadims[0]/2)] = 1.0
  mask[where (mask gt data.datadims[0]/2)] = 0.0
  mask = mask gt 0.5

  dset_id = H5D_open(group_id,'xtalname')
  z = H5D_read(dset_id) 
  data.xtalname = strtrim(string(z[0]))
  H5D_close,dset_id
    CBEDprint,'Xtalname = ->'+data.xtalname+'<-'
  WIDGET_CONTROL, SET_VALUE=data.xtalname, widget_s.xtalname

; accelerating voltage
  dset_id = H5D_open(group_id,'voltage')
  z = H5D_read(dset_id) 
  data.voltage = z[0] * 1000.0
  H5D_close,dset_id
  data.wavelength= 1226.39/sqrt(data.voltage + 0.97845E-6 * data.voltage^2)
    CBEDprint,'Wave length = '+string(data.wavelength,FORMAT="(F7.4)")
  WIDGET_CONTROL, SET_VALUE=string(data.wavelength,FORMAT="(F7.4)"), widget_s.wavelength

; beam convergence
  dset_id = H5D_open(group_id,'convergence')
  z = H5D_read(dset_id) 
  data.thetac = z[0]
  H5D_close,dset_id
    CBEDprint,'Beam convergence = '+string(data.thetac,FORMAT="(F7.3)")
  WIDGET_CONTROL, SET_VALUE=string(data.thetac,FORMAT="(F7.3)"), widget_s.thetac

; wave vector indices (3 longints)
  dset_id = H5D_open(group_id,'k')
  z = H5D_read(dset_id) 
  data.wavek = z[0:2]
  H5D_close,dset_id
  wv = '['+string(data.wavek[0],format="(I3)")+' '+ string(data.wavek[1],format="(I3)")+' '+ string(data.wavek[2],format="(I3)")+']'
    CBEDprint,'Wave vector = '+wv
  WIDGET_CONTROL, SET_VALUE=wv, widget_s.wavek

; foil normal indices (3 longints)
  dset_id = H5D_open(group_id,'fn')
  z = H5D_read(dset_id) 
  data.fn= z[0:2]
  H5D_close,dset_id
  wv = '['+string(data.fn[0],format="(I3)")+' '+ string(data.fn[1],format="(I3)")+' '+ string(data.fn[2],format="(I3)")+']'
    CBEDprint,'Foil normal = '+wv
  WIDGET_CONTROL, SET_VALUE=wv, widget_s.fn

; dmin value (not editable or viewable)
  dset_id = H5D_open(group_id,'dmin')
  z = H5D_read(dset_id) 
  data.dmin= z[0]
  H5D_close,dset_id

; maximum HOLZ layer number 
  dset_id = H5D_open(group_id,'maxHOLZ')
  z = H5D_read(dset_id) 
  data.maxHOLZ = z[0]
  H5D_close,dset_id
    CBEDprint,'Maximum HOLZ layer number = '+string(data.maxHOLZ,FORMAT="(I3)")
  WIDGET_CONTROL, SET_VALUE=string(data.maxHOLZ,FORMAT="(I5)"), widget_s.maxHOLZ

; starting thickness and thickness increment
; (these are not shown in the main widget, but they are shown in a droplist widget in other areas)
  dset_id = H5D_open(group_id,'startthick')
  z = H5D_read(dset_id) 
  data.startthick = z[0]
  H5D_close,dset_id
  dset_id = H5D_open(group_id,'thickinc')
  z = H5D_read(dset_id) 
  data.thickinc = z[0]
  H5D_close,dset_id
    CBEDprint,' Starting thickness [nm]   = '+string(data.startthick,FORMAT="(F6.3)")
    CBEDprint,' Thickness increment [nm]  = '+string(data.thickinc,FORMAT="(F6.3)")

 H5G_CLOSE, group_id
 group_id = H5G_open(file_id,'EMData')

; next we load the actual diffraction disks; we'll do this with the hyperslab mechanism so we can use the progress bar ...
  CBEDprogressbar,0.0
    CBEDprint,'Loading diffraction data arrays',/blank
  disks = fltarr(data.datadims)

; open the dataset and read the hyperslab sections
  slabID = H5D_OPEN(group_id,'disks')
  dataspace_ID = H5D_GET_SPACE(slabID)

  count = data.datadims
  count[3] = 1L

  for i=0L,data.datadims[3]-1 do begin
    start = [0,0,0,i]
    H5S_SELECT_HYPERSLAB, dataspace_ID, start, count, /RESET
    memory_space_ID = H5S_CREATE_SIMPLE(count)

    dd = H5D_READ(slabID, FILE_SPACE=dataspace_ID, MEMORY_SPACE=memory_space_ID)
    disks[0,0,0,i] = dd
    CBEDprogressbar,100.0*float(i)/float(data.datadims[3])
  endfor
  CBEDprogressbar,100.0
  H5S_CLOSE, memory_space_ID
  H5S_CLOSE, dataspace_ID
  H5D_CLOSE, slabID

; familyhkl -> gvecs
  dset_id = H5D_open(group_id,'familyhkl')
  gvecs = H5D_read(dset_id) 
  H5D_close,dset_id

; familymult -> gmult
  dset_id = H5D_open(group_id,'familymult')
  gmult = H5D_read(dset_id) 
  H5D_close,dset_id

; familytwotheta -> gtt
  dset_id = H5D_open(group_id,'familytwotheta')
  gtt = H5D_read(dset_id) 
  H5D_close,dset_id

; diskoffset -> gxy
  dset_id = H5D_open(group_id,'diskoffset')
  gxy = H5D_read(dset_id) 
  H5D_close,dset_id

; get the HOLZ identifier list
  HOLZlist = indgen(data.datadims[3])
  HOLZlist[0] = 0	; transmitted beam
  for i=1,data.datadims[3]-1 do begin
    HOLZlist[i] = abs( gvecs[0,i]*data.wavek[0]+gvecs[1,i]*data.wavek[1]+gvecs[2,i]*data.wavek[2] )
  endfor
    
; then determine how many there are in each layer
  numHOLZ = indgen(data.maxHOLZ+1)
  for i=0,data.maxHOLZ do begin
    q=where(HOLZlist eq i,cnt)
    numHOLZ[i] = cnt
  endfor

; (de)activate the LACBED and CBED buttons
  WIDGET_CONTROL, widget_s.startLACBED, sensitive=1
  WIDGET_CONTROL, widget_s.startCBED, sensitive=1
  WIDGET_CONTROL, widget_s.startMBCBED, sensitive=0

; old code use for EMmbcbed program
;   if ( keyword_set(MBCBED) or (progname eq 'CTEMmbcbed.f90') ) then begin
;     CBEDprogressbar,0.0
;       CBEDprint,'Allocating memory for diffraction data array',/blank
;       disks = fltarr(dims[0],dims[1],dims[2])
;       slice = fltarr(dims[0],dims[1])
;       for i=0,dims[2]-1 do begin
; 	readu,1,slice
; 	disks[0:*,0:*,i] = reverse(slice,2)	; correct for the fact that the origin is in the top left for the Fortran array
;         CBEDprogressbar,100.0*float(i)/float(data.datadims[2])
;       endfor
;     CBEDprogressbar,100.0
;     close,1
; ; (de)activate the LACBED and CBED buttons
;     WIDGET_CONTROL, widget_s.startLACBED, sensitive=0
;     WIDGET_CONTROL, widget_s.startCBED, sensitive=0
;     WIDGET_CONTROL, widget_s.startMBCBED, sensitive=1
; end

; and close the data file
  H5G_close,group_id
  H5F_close,file_id
    CBEDprint,'Completed reading data file',/blank

; there are a few parameters that need to be reset after reading a new file
; [no need to write them to widgets since there shouldn't be any open immediately after a new file has been read]
data.thicksel = 0
data.famsel = 0
data.diskrotation = 0.0
data.dfdisplaymode = 0
data.CBEDmode = 0
data.Lauex = 0.0
data.Lauey = 0.0
data.oldLauex = 0.0
data.oldLauey = 0.0


skipall:

end
