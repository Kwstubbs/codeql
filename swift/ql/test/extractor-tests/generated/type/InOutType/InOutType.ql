// generated by codegen/codegen.py, do not edit
import codeql.swift.elements
import TestUtils

from InOutType x, string getName, Type getCanonicalType, Type getObjectType
where
  toBeTested(x) and
  not x.isUnknown() and
  getName = x.getName() and
  getCanonicalType = x.getCanonicalType() and
  getObjectType = x.getObjectType()
select x, "getName:", getName, "getCanonicalType:", getCanonicalType, "getObjectType:",
  getObjectType
