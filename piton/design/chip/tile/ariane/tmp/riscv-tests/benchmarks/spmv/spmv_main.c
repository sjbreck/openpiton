// See LICENSE for license details.

//**************************************************************************
// Double-precision sparse matrix-vector multiplication benchmark
//--------------------------------------------------------------------------

#include "util.h"

//--------------------------------------------------------------------------
// Input/Reference Data

#include "dataset1.h"

void spmv(int r, const double* val, const int* idx, const double* x,
          const int* ptr, double* y)
{
  for (int i = 0; i < r; i++)
  {
    int k;
    double yi0 = 0;
    for (k = ptr[i]; k < ptr[i+1]; k++)
    {
      yi0 += val[k]*x[idx[k]];
    }
    y[i] = (yi0);
  }
}

//--------------------------------------------------------------------------
// Main

int main( int argc, char* argv[] )
{
  double y[R];

#if PREALLOCATE
  //spmv(R, val, idx, x, ptr, y);
#endif

  setStats(1);
  spmv(R, val, idx, x, ptr, y);
  setStats(0);

  return verifyDouble(R, y, verify_data);
}
