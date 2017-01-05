# This file is part of ASAP.
# Please see LICENSE.txt for copyright and licensing information.

add_llvm_library(LLVMSanityChecks
  AsapPass.cpp
  AsapPassBase.cpp
  CostModel.cpp
  ExitInsteadOfAbort.cpp
  GCOV.cpp
  OverheadEstimation.cpp
  SanityCheckCoverageCost.cpp
  SanityCheckGcovCost.cpp
  SanityCheckInstructions.cpp
  SanityCheckSampledCost.cpp
  SanityChecks.cpp
  utils.cpp

  ADDITIONAL_HEADER_DIRS
  ${LLVM_MAIN_INCLUDE_DIR}/llvm/Transforms/SanityChecks
  )

add_dependencies(LLVMSanityChecks LLVMInstrumentation LLVMSymbolize)

# Create symlinks for asap-clang.rb
add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/bin/asap-clang
  COMMAND cd ${CMAKE_BINARY_DIR}/bin && ln -sf ${CMAKE_CURRENT_SOURCE_DIR}/asap-clang.rb asap-clang
  COMMENT Creating symlink for asap-clang
  VERBATIM)
add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/bin/asap-clang++
  COMMAND cd ${CMAKE_BINARY_DIR}/bin && ln -sf ${CMAKE_CURRENT_SOURCE_DIR}/asap-clang.rb asap-clang++
  COMMENT Creating symlink for asap-clang++
  VERBATIM)
add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/bin/asap-ranlib
  COMMAND cd ${CMAKE_BINARY_DIR}/bin && ln -sf ${CMAKE_CURRENT_SOURCE_DIR}/asap-clang.rb asap-ranlib
  COMMENT Creating symlink for asap-ranlib
  VERBATIM)
add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/bin/asap-ar
  COMMAND cd ${CMAKE_BINARY_DIR}/bin && ln -sf ${CMAKE_CURRENT_SOURCE_DIR}/asap-clang.rb asap-ar
  COMMENT Creating symlink for asap-ar
  VERBATIM)
add_custom_target(asap_clang_symlinks
  ALL
  DEPENDS ${CMAKE_BINARY_DIR}/bin/asap-clang
          ${CMAKE_BINARY_DIR}/bin/asap-clang++
          ${CMAKE_BINARY_DIR}/bin/asap-ranlib
          ${CMAKE_BINARY_DIR}/bin/asap-ar)
