/**
 * Provides a taint tracking configuration for reasoning about polynomial
 * regular expression denial-of-service attacks.
 *
 * Note, for performance reasons: only import this file if
 * `PolynomialReDoSFlow` is needed. Otherwise,
 * `PolynomialReDoSCustomizations` should be imported instead.
 */

private import codeql.ruby.DataFlow
private import codeql.ruby.TaintTracking

private module PolynomialReDoSConfig implements DataFlow::ConfigSig {
  private import PolynomialReDoSCustomizations::PolynomialReDoS

  predicate isSource(DataFlow::Node source) { source instanceof Source }

  predicate isSink(DataFlow::Node sink) { sink instanceof Sink }

  predicate isBarrier(DataFlow::Node node) { node instanceof Sanitizer }

  // Diff-informedness is disabled because of RegExpTerms having incorrect locations when
  // the regexp is parsed from a string arising from constant folding.
  predicate observeDiffInformedIncrementalMode() { none() }

  Location getASelectedSinkLocation(DataFlow::Node sink) {
    result = sink.(Sink).getHighlight().getLocation()
    or
    result = sink.(Sink).getRegExp().getRootTerm().getLocation()
  }
}

/**
 * Taint-tracking for detecting polynomial regular
 * expression denial of service vulnerabilities.
 */
module PolynomialReDoSFlow = TaintTracking::Global<PolynomialReDoSConfig>;
