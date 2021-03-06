title: Notes
author: Laura Nichols
date: 7/3/2019

* Can use `xcrysden` to visualize QE input and output
* Can convert from QE output to xsf (VASP format) using `PW/tools/pwo2xsf.sh`
* There are four different types of extraction from the PWscf output:
  * initial structure: the one reported from the input at the beginning of the output file (for the SCF calculation one should select this option)
  * latest structure: the latest structure in the output file; if the latest structure is the optimized structure, then this one is extracted. For an SCF calculation only initial structure is reported and the "latest structure" extraction extracts noting in this case
  * optimized structure: extracts the optimized structure, if it is not present it extracts nothing
  * all structures as animation 
* *What is the purpose of the QE calculation?* --> **Explore the TME program**
* PC stands for perfect crystal and SD stands for solid defect
* Things to make program work on HPC
  * `chmod +x <QE path>/configure`
  * `chmod +x <QE path>/install/configure`
  * `module swap PrgEnv-intel PrgEnv-gnu`
  * `module load mpi`
  * `module load intel`
