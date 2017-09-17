/*****************************************************************************

YASK: Yet Another Stencil Kernel
Copyright (c) 2014-2017, Intel Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

* The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.

*****************************************************************************/

#include "yask.hpp"
using namespace std;

namespace yask {

    // Make a new grid.
    YkGridPtr StencilContext::newGrid(const std::string& name,
                                      const GridDimNames& dims,
                                      bool is_visible) {

        // Check dims.
        int ndims = dims.size();
        int step_posn = 0;      // 0 => not used.
        int inner_posn = 0;     // 0 => not used.
        int num_vec_dims = 0;
        set<string> seenDims;
        for (int i = 0; i < ndims; i++) {

            // Already used?
            if (seenDims.count(dims[i])) {
                cerr << "Error: cannot create grid '" << name <<
                    "': dimension '" << dims[i] << "' used more than once.\n";
                exit_yask(1);
            }
            
            // Step dim?
            if (dims[i] == _dims->_step_dim) {
                step_posn = i + 1;
                if (i > 0) {
                    cerr << "Error: cannot create grid '" << name <<
                        "' because step dimension '" << dims[i] <<
                        "' must be first dimension.\n";
                    exit_yask(1);
                }
            }

            // Vec dim?
            else if (_dims->_vec_fold_pts.lookup(dims[i])) {
                num_vec_dims++;

                // Inner dim?
                if (dims[i] == _dims->_inner_dim)
                    inner_posn = i + 1;
            }
        }

        // Use a folded grid iff all vectorized dims are
        // used in this grid (and there is at least one).
        bool do_fold = (num_vec_dims >= 1) &&
            (num_vec_dims == _dims->_vec_fold_pts.getNumDims());
        
        // NB: the behavior of this algorithm must follow that in the
        // YASK compiler to allow grids created via new_grid() to share
        // storage with those created via the compiler.
        YkGridPtr gp;
        if (ndims == 0) {
            gp = make_shared<YkElemGrid<Layout_0d, false>>(_dims, name, dims, &_ostr);
        }
        
        // Include auto-gen code for all other caes.
#include "yask_grid_code.hpp"
            
        if (!gp) {
            cerr << "Error in new_grid: cannot create grid '" << name <<
                "' with " << dims.size() << " dimensions; only up to " << MAX_DIMS <<
                " dimensions supported.\n";
            exit_yask(1);
        }

        // Add to context.
        if (is_visible)
            addGrid(gp, false);     // mark as non-output grid; TODO: determine if this is ok.

        // Set default sizes from settings and get offset, if set.
        if (is_visible)
            update_grids();

        return gp;
    }
} // namespace yask.
