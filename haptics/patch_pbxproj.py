#!/usr/bin/env python3
"""Patch liblove.xcodeproj/project.pbxproj to include haptics.mm in the build."""
import sys, os

proj = os.path.join(os.path.dirname(__file__), '..', 'ios', 'love-source', 'platform', 'xcode', 'liblove.xcodeproj', 'project.pbxproj')
proj = os.path.normpath(proj)

with open(proj) as f:
    content = f.read()

if 'haptics.mm' in content:
    print('haptics.mm already in pbxproj, skipping')
    sys.exit(0)

# File reference
uid1 = 'DEADBEEFAABBCCDDEEFF0001'
uid2 = 'DEADBEEFAABBCCDDEEFF0002'
uid3 = 'DEADBEEFAABBCCDDEEFF0003'

ref_line = '\t\t\t{} /* haptics.mm */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.cpp.objcpp; path = "../../../../haptics/haptics.mm"; sourceTree = "<group>"; }};'.format(uid1)
bf_line1 = '\t\t\t{} /* haptics.mm in Sources */ = {{isa = PBXBuildFile; fileRef = {} /* haptics.mm */; }};'.format(uid2, uid1)
bf_line2 = '\t\t\t{} /* haptics.mm in Sources */ = {{isa = PBXBuildFile; fileRef = {} /* haptics.mm */; }};'.format(uid3, uid1)

# Add build file entries before End PBXBuildFile section
content = content.replace(
    '/* End PBXBuildFile section */',
    bf_line1 + '\n' + bf_line2 + '\n/* End PBXBuildFile section */'
)

# Add file reference before End PBXFileReference section
content = content.replace(
    '/* End PBXFileReference section */',
    ref_line + '\n/* End PBXFileReference section */'
)

# Add to both Sources build phases (love-ios and liblove-ios)
insert1 = '\t\t\t\t\t' + uid2 + ' /* haptics.mm in Sources */,\n'
content = content.replace(
    'buildPhases = (\n',
    'buildPhases = (\n' + insert1,
    1
)
content = content.replace(
    'buildActionMask = 2147483647;\n\t\t\t\tfiles = (\n',
    'buildActionMask = 2147483647;\n\t\t\t\tfiles = (\n' + insert1.replace(uid2, uid3),
    1
)

with open(proj, 'w') as f:
    f.write(content)

print('Patched pbxproj with haptics.mm reference')
