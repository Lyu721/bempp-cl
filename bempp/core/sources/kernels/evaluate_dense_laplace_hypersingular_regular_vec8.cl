#include "bempp_base_types.h"
#include "bempp_helpers.h"
#include "bempp_spaces.h"
#include "kernels.h"

__kernel __attribute__((vec_type_hint(REALTYPE8))) __kernel void
evaluate_dense_laplace_hypersingular_regular(
    __global uint* testIndices, __global uint* trialIndices,
    __global int *testNormalSigns, __global int *trialNormalSigns,
    __global REALTYPE* testGrid, __global REALTYPE* trialGrid,
    __global uint* testConnectivity, __global uint* trialConnectivity,
    __global uint* testLocal2Global, __global uint* trialLocal2Global,
    __global REALTYPE* testLocalMultipliers,
    __global REALTYPE* trialLocalMultipliers, __constant REALTYPE* quadPoints,
    __constant REALTYPE* quadWeights, __global REALTYPE* globalResult,
    int nTest, int nTrial, char gridsAreDisjoint) {
  /* Variable declarations */

  size_t gid[2] = {get_global_id(0), get_global_id(1)};
  size_t offset = get_global_offset(1);

  size_t testIndex = testIndices[gid[0]];
  size_t trialIndex[8] = {trialIndices[offset + 8 * (gid[1] - offset) + 0],
                          trialIndices[offset + 8 * (gid[1] - offset) + 1],
                          trialIndices[offset + 8 * (gid[1] - offset) + 2],
                          trialIndices[offset + 8 * (gid[1] - offset) + 3],
                          trialIndices[offset + 8 * (gid[1] - offset) + 4],
                          trialIndices[offset + 8 * (gid[1] - offset) + 5],
                          trialIndices[offset + 8 * (gid[1] - offset) + 6],
                          trialIndices[offset + 8 * (gid[1] - offset) + 7]};

  size_t testQuadIndex;
  size_t trialQuadIndex;
  size_t i;
  size_t j;
  size_t k;
  size_t globalRowIndex;
  size_t globalColIndex;

  REALTYPE3 testGlobalPoint;
  REALTYPE8 trialGlobalPoint[3];

  REALTYPE3 testCorners[3];
  REALTYPE8 trialCorners[3][3];

  uint testElement[3];
  uint trialElement[8][3];

  uint myTestLocal2Global[NUMBER_OF_TEST_SHAPE_FUNCTIONS];
  uint myTrialLocal2Global[8][NUMBER_OF_TRIAL_SHAPE_FUNCTIONS];

  REALTYPE myTestLocalMultipliers[NUMBER_OF_TEST_SHAPE_FUNCTIONS];
  REALTYPE myTrialLocalMultipliers[8][NUMBER_OF_TRIAL_SHAPE_FUNCTIONS];

  REALTYPE3 testJac[2];
  REALTYPE8 trialJac[2][3];

  REALTYPE3 testNormal;
  REALTYPE8 trialNormal[3];

  REALTYPE2 testPoint;
  REALTYPE2 trialPoint;

  REALTYPE testIntElem;
  REALTYPE8 trialIntElem;

  REALTYPE testInv[2][2];
  REALTYPE8 trialInv[2][2];

  REALTYPE8 trialCurl[3][3];
  REALTYPE3 testCurl[3];

  REALTYPE8 basisProduct[3][3];

  REALTYPE8 trialInvBasis[2][3];
  REALTYPE8 trialElementGradient[3][3];

  REALTYPE8 kernelValue;
  REALTYPE8 tempResult;
  REALTYPE8 shapeIntegral;

  getCorners(testGrid, testIndex, testCorners);
  getCornersVec8(trialGrid, trialIndex, trialCorners);

  getElement(testConnectivity, testIndex, testElement);
  getElementVec8(trialConnectivity, trialIndex, trialElement);

  getLocal2Global(testLocal2Global, testIndex, myTestLocal2Global,
                  NUMBER_OF_TEST_SHAPE_FUNCTIONS);
  getLocal2GlobalVec8(trialLocal2Global, trialIndex, &myTrialLocal2Global[0][0],
                      NUMBER_OF_TRIAL_SHAPE_FUNCTIONS);

  getLocalMultipliers(testLocalMultipliers, testIndex, myTestLocalMultipliers,
                      NUMBER_OF_TEST_SHAPE_FUNCTIONS);
  getLocalMultipliersVec8(trialLocalMultipliers, trialIndex,
                          &myTrialLocalMultipliers[0][0],
                          NUMBER_OF_TRIAL_SHAPE_FUNCTIONS);

  getJacobian(testCorners, testJac);
  getJacobianVec8(trialCorners, trialJac);

  getNormalAndIntegrationElement(testJac, &testNormal, &testIntElem);
  getNormalAndIntegrationElementVec8(trialJac, trialNormal, &trialIntElem);

  updateNormals(testIndex, testNormalSigns, &testNormal);
  updateNormalsVec8(trialIndex, trialNormalSigns, trialNormal);

  testInv[0][0] = dot(testJac[1], testJac[1]);
  testInv[1][1] = dot(testJac[0], testJac[0]);
  testInv[0][1] = -dot(testJac[0], testJac[1]);
  testInv[1][0] = testInv[0][1];

  trialInv[0][0] = M_ZERO;
  trialInv[1][1] = M_ZERO;
  trialInv[0][1] = M_ZERO;

  for (i = 0; i < 3; ++i) {
    trialInv[0][0] += trialJac[1][i] * trialJac[1][i];
    trialInv[0][1] -= trialJac[0][i] * trialJac[1][i];
    trialInv[1][1] += trialJac[0][i] * trialJac[0][i];
  }

  trialInv[1][0] = trialInv[0][1];

  testCurl[0] =
      cross(testNormal, testJac[0] * (-testInv[0][0] - testInv[0][1]) +
                            testJac[1] * (-testInv[1][0] - testInv[1][1]));
  testCurl[1] = cross(testNormal,
                      testJac[0] * testInv[0][0] + testJac[1] * testInv[1][0]);
  testCurl[2] = cross(testNormal,
                      testJac[0] * testInv[0][1] + testJac[1] * testInv[1][1]);

  for (i = 0; i < 2; ++i) {
    trialInvBasis[i][0] = -trialInv[i][0] - trialInv[i][1];
    trialInvBasis[i][1] = trialInv[i][0];
    trialInvBasis[i][2] = trialInv[i][1];
  }

  for (i = 0; i < 3; ++i)
    for (j = 0; j < 3; ++j) {
      trialElementGradient[j][i] = 0;
      for (k = 0; k < 2; ++k)
        trialElementGradient[j][i] += trialJac[k][i] * trialInvBasis[k][j];
    }

  for (i = 0; i < 3; ++i) {
    trialCurl[i][0] = trialNormal[1] * trialElementGradient[i][2] -
                      trialNormal[2] * trialElementGradient[i][1];
    trialCurl[i][1] = trialNormal[2] * trialElementGradient[i][0] -
                      trialNormal[0] * trialElementGradient[i][2];
    trialCurl[i][2] = trialNormal[0] * trialElementGradient[i][1] -
                      trialNormal[1] * trialElementGradient[i][0];
  }

  for (i = 0; i < 3; ++i)
    for (j = 0; j < 3; ++j) {
      basisProduct[i][j] = testCurl[i].x * trialCurl[j][0] +
                           testCurl[i].y * trialCurl[j][1] +
                           testCurl[i].z * trialCurl[j][2];
    }

  shapeIntegral = M_ZERO;

  for (testQuadIndex = 0; testQuadIndex < NUMBER_OF_QUAD_POINTS;
       ++testQuadIndex) {
    testPoint = (REALTYPE2)(quadPoints[2 * testQuadIndex], quadPoints[2 * testQuadIndex + 1]);
    testGlobalPoint = getGlobalPoint(testCorners, &testPoint);
    tempResult = M_ZERO;

    for (trialQuadIndex = 0; trialQuadIndex < NUMBER_OF_QUAD_POINTS;
         ++trialQuadIndex) {
      trialPoint = (REALTYPE2)(quadPoints[2 * trialQuadIndex], quadPoints[2 * trialQuadIndex + 1]);
      getGlobalPointVec8(trialCorners, &trialPoint, trialGlobalPoint);
      KERNEL(vec8)
      (testGlobalPoint, trialGlobalPoint, testNormal, trialNormal,
       &kernelValue);
      tempResult += quadWeights[trialQuadIndex] * kernelValue;
    }

    shapeIntegral += tempResult * quadWeights[testQuadIndex];
  }

  // the Jacobian Inverse must by divded by the squared of the integration
  // elements. The integral must be multiplied by the integration elements. So
  // in total we have to divide once.

  shapeIntegral /= (testIntElem * trialIntElem);

  for (i = 0; i < NUMBER_OF_TEST_SHAPE_FUNCTIONS; ++i)
    for (j = 0; j < NUMBER_OF_TRIAL_SHAPE_FUNCTIONS; ++j)
      basisProduct[i][j] *= shapeIntegral;

  for (int vecIndex = 0; vecIndex < 8; ++vecIndex)
    if (!elementsAreAdjacent(testElement, trialElement[vecIndex],
                             gridsAreDisjoint)) {
      for (i = 0; i < NUMBER_OF_TEST_SHAPE_FUNCTIONS; ++i)
        for (j = 0; j < NUMBER_OF_TRIAL_SHAPE_FUNCTIONS; ++j) {
          globalRowIndex = myTestLocal2Global[i];
          globalColIndex = myTrialLocal2Global[vecIndex][j];
          globalResult[globalRowIndex * nTrial + globalColIndex] +=
              ((REALTYPE*)(&basisProduct[i][j]))[vecIndex] *
              myTestLocalMultipliers[i] * myTrialLocalMultipliers[vecIndex][j];
        }
    }
}
