
# Update build structure
This project fetches several open source projects, compiles some
of them, and creates a binary distribution. A CI/CD workflow 
performs this process across several platform variants.

Make the following updates to the build and CI/CD flow:

- Move to using CMake as the build tool instead of the shell script (scripts/build_linux.sh).
- Fetch and build the external packages using cmake ExternalProject
- Support both tagged releases and the latest branch on git main
- Fetch uvm (see ivpm.yaml for url). The 'src' subdir must be installed
  as <instdir>/share/uvm/src. 

First test the build locally. Ensure everything passes