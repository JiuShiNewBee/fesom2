# This file is part of pyfesom
#use following for debugging wherever required:
#import pdb
#pdb.set_trace()
################################################################################
#
# Original code by Dmitry Sidorenko, 2013
#
# Modifications:
#   Nikolay Koldunov, 2016
#          - optimisation of reading ASCII fies (add pandas dependency)
#          - move loading and processing of the mesh to the mesh class itself
#
################################################################################

import pandas as pd
import numpy as np
from netCDF4 import Dataset
from ut import scalar_r2g
from scipy.io import netcdf # replace it with netCDF4
import os
import logging
import time
import pickle

def load_mesh(path, abg = [50, 15, -90], usepickle = True):
    path=os.path.abspath(path)
    pickle_file = os.path.join(path,'pickle_mesh')

    if usepickle and (os.path.isfile(pickle_file)):
        print("The *usepickle = True* and the pickle file (*pickle_mesh*) exists.\n We load the mesh from it.")

        ifile = open(pickle_file, 'r')
        mesh = pickle.load(ifile)
        ifile.close()
        return mesh

    elif (usepickle==True) and (os.path.isfile(pickle_file)==False):
        print('The *usepickle = True*, but the pickle file (*pickle_mesh*) do not exist.')
        mesh = fesom_mesh(path=path, abg=abg)
        logging.info('Use pickle to save the mesh information')
        print('Save mesh to binary format')
        outfile = open(os.path.join(path,'pickle_mesh'), 'wb')
        pickle.dump(mesh, outfile)
        outfile.close()
        return mesh

    elif usepickle==False:
        mesh = fesom_mesh(path=path, abg=abg)
        return mesh


class fesom_mesh(object):
    """ Creates instance of the FESOM mesh.

    This class creates instance that contain information
    about FESOM mesh. At present the class works with 
    ASCII representation of the FESOM grid, but should be extended 
    to be able to read also netCDF version (probably UGRID convention).

    Minimum requirement is to provide the path to the directory, 
    where following files should be located (not nessesarely all of them will
    be used):

    - nod2d.out
    - elem2d.out
    - aux3d.out

    Parameters
    ----------
    path : str
        Path to the directory with mesh files

    abg : list
        alpha, beta and gamma Euler angles. Default [50, 15, -90]

    toread : list
        list of the grid type to read. Possible options are '2d' and '3d'.
        By default we read both 2d and 3d (['2d','3d']), but it might take
        some time for large meshes and could blow up when there is 
        not enough memory.

    Attributes
    ----------
    path : str
        Path to the directory with mesh files
    x2 : array
        x position (lon) of the surface node
    y2 : array
        y position (lat) of the surface node
    n2d : int
        number of 2d nodes
    e2d : int
        number of 2d elements (triangles)
    nlev : int
        number of vertical levels
    zlevs : array
        array of vertical level depths
    voltri

    existing instances are: path, n2d, e2d,
    nlev, zlevs, x2, y2, elem, no_cyclic_elem, alpha, beta, gamma"""
    def __init__(self, path, abg = [50, 15, -90]):
        self.path=os.path.abspath(path)

        if not os.path.exists(self.path):
            raise IOError("The path \"{}\" does not exists".format(self.path))


        self.alpha=abg[0]
        self.beta=abg[1]
        self.gamma=abg[2]

        self.nod2dfile=os.path.join(self.path,'nod2d.out')
        self.elm2dfile=os.path.join(self.path,'elem2d.out')
        self.aux3dfile=os.path.join(self.path,'aux3d.out')

        self.e2d=0
        self.nlev=0
        self.zlevs= []
        self.topo=[]
        self.voltri=[]

        logging.info('load 2d part of the grid')
        start = time.clock()
        self.read2d()
        end = time.clock()
        print('Load 2d part of the grid in {} second(s)'.format(str(int(end-start))))
        
    def read2d(self):
        file_content = pd.read_csv(self.nod2dfile, delim_whitespace=True, skiprows=1, \
                                      names=['node_number','x','y','flag'] )
        self.x2=file_content.x.values
        self.y2=file_content.y.values
        self.n2d=len(self.x2)

        file_content = pd.read_csv(self.elm2dfile, delim_whitespace=True, skiprows=1, \
                                              names=['first_elem','second_elem','third_elem'])
        self.elem=file_content.values-1
        self.e2d=np.shape(self.elem)[0]

                ########################################### 
        #here we compute the volumes of the triangles
        #this should be moved into fesom generan mesh output netcdf file
        #
        r_earth=6371000.0
        rad=np.pi/180
        edx=self.x2[self.elem]
        edy=self.y2[self.elem]
        ed=np.array([edx, edy])

        jacobian2D=ed[:, :, 1]-ed[:, :, 0]
        jacobian2D=np.array([jacobian2D, ed[:, :, 2]-ed[:, :, 0]])
        for j in range(2):
            mind = [i for (i, val) in enumerate(jacobian2D[j,0,:]) if val > 355]
            pind = [i for (i, val) in enumerate(jacobian2D[j,0,:]) if val < -355]
            jacobian2D[j,0,mind]=jacobian2D[j,0,mind]-360
            jacobian2D[j,0,pind]=jacobian2D[j,0,pind]+360

        jacobian2D=jacobian2D*r_earth*rad

        for k in range(2):
            jacobian2D[k,0,:]=jacobian2D[k,0,:]*np.cos(edy*rad).mean(axis=1)

        self.voltri = abs(np.linalg.det(np.rollaxis(jacobian2D, 2)))/2.
        
        # compute the 2D lump operator
        cnt=np.array((0,)*self.n2d)
        self.lump2=np.array((0.,)*self.n2d)
        for i in range(3):
            for j in range(self.e2d):
                n=self.elem[j,i]
                #cnt[n]=cnt[n]+1
                self.lump2[n]=self.lump2[n]+self.voltri[j]
        self.lump2=self.lump2/3.

        self.x2, self.y2 = scalar_r2g(self.alpha,self.beta,self.gamma,self.x2, self.y2)
        d=self.x2[self.elem].max(axis=1) - self.x2[self.elem].min(axis=1)
        self.no_cyclic_elem = [i for (i, val) in enumerate(d) if val < 100]

        with open(self.aux3dfile) as f:
            self.nlev=int(next(f))
            self.zlev=np.array([next(f).rstrip() for x in range(self.nlev)]).astype(float)
            
        return self


    def __repr__(self):
        meshinfo = '''
FESOM mesh:
path                  = {}
alpha, beta, gamma    = {}, {}, {}
number of 2d nodes    = {}
number of 2d elements = {}
number of 3d nodes    = {}

        '''.format(self.path,
                   str(self.alpha),
                   str(self.beta),
                   str(self.gamma),
                   str(self.n2d),
                   str(self.e2d),
                   str(self.n3d))
        return meshinfo 
    def __str__(self):
        return __repr__(self)
    
def ind_for_depth(depth, mesh):
    # find the model depth index that is closest to the required depth
    arr=([abs(abs(z)-abs(depth)) for z in mesh.zlev])
    v, i= min((v, i) for (i, v) in enumerate(arr))    
    dind=i
    return dind
        
def read_fesom_slice(str_id, records, year, mesh, result_path, runid, ilev=0, how='mean'): 
        #print(['reading year '+str(year)+':'])
    ncfile =result_path+'/'+str_id+'.'+runid+'.'+str(year)+'.nc'
    print(['reading ', ncfile])
    f = Dataset(ncfile, 'r')
    # dimensions of the netcdf variable
    ncdims=f.variables[str_id].shape
    # indexies for reading 2D part
    if (ncdims[1]==mesh.n2d):
        print('data at nodes')
    elif (ncdims[1]==mesh.e2d):
        print('data on elements')
    else:
        raise IOError('not existing dimension '+str(ncdims[1]))    
    
    dim=[records, np.arange(ncdims[1])]
    data=np.zeros(shape=(ncdims[1]))    
    # add 3rd index if reading a slice from 3D data
    if (len(ncdims)==3):
       dim.append(ilev)
        
    if how=='mean':
       data = data+f.variables[str_id][dim].mean(axis=0)
    elif how=='max':
        data = data+f.variables[str_id][dim].max(axis=0)
    f.close()
    return data