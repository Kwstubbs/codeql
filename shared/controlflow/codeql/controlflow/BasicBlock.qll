/**
 * This modules provides an implementation of a basic block class based on a
 * control flow graph implementation.
 *
 * INTERNAL use only. This is an experimental API subject to change without
 * notice.
 */
overlay[local?]
module;

private import codeql.util.Location

/** Provides the language-specific input specification. */
signature module InputSig<LocationSig Location> {
  class SuccessorType;

  /** Hold if `t` represents a conditional successor type. */
  predicate successorTypeIsCondition(SuccessorType t);

  /** A delineated part of the AST with its own CFG. */
  class CfgScope;

  /** The class of control flow nodes. */
  class Node {
    string toString();

    /** Gets the location of this control flow node. */
    Location getLocation();
  }

  /** Gets the CFG scope in which this node occurs. */
  CfgScope nodeGetCfgScope(Node node);

  /** Gets an immediate successor of this node. */
  Node nodeGetASuccessor(Node node, SuccessorType t);

  /**
   * Holds if `node` represents an entry node to be used when calculating
   * dominance.
   */
  predicate nodeIsDominanceEntry(Node node);

  /**
   * Holds if `node` represents an exit node to be used when calculating
   * post dominance.
   */
  predicate nodeIsPostDominanceExit(Node node);
}

/**
 * Provides a basic block construction on top of a control flow graph.
 */
module Make<LocationSig Location, InputSig<Location> Input> {
  private import Input

  /**
   * A basic block, that is, a maximal straight-line sequence of control flow nodes
   * without branches or joins.
   */
  final class BasicBlock extends TBasicBlockStart {
    /** Gets the CFG scope of this basic block. */
    CfgScope getScope() { result = nodeGetCfgScope(this.getFirstNode()) }

    /** Gets the location of this basic block. */
    Location getLocation() { result = this.getFirstNode().getLocation() }

    /** Gets an immediate successor of this basic block, if any. */
    BasicBlock getASuccessor() { result = this.getASuccessor(_) }

    /** Gets an immediate successor of this basic block of a given type, if any. */
    BasicBlock getASuccessor(SuccessorType t) { bbSuccessor(this, result, t) }

    /** Gets an immediate predecessor of this basic block, if any. */
    BasicBlock getAPredecessor() { result.getASuccessor(_) = this }

    /** Gets an immediate predecessor of this basic block of a given type, if any. */
    BasicBlock getAPredecessor(SuccessorType t) { result.getASuccessor(t) = this }

    /** Gets the control flow node at a specific (zero-indexed) position in this basic block. */
    Node getNode(int pos) { result = getNode(this, pos) }

    /** Gets a control flow node in this basic block. */
    Node getANode() { result = this.getNode(_) }

    /** Gets the first control flow node in this basic block. */
    Node getFirstNode() { this = TBasicBlockStart(result) }

    /** Gets the last control flow node in this basic block. */
    Node getLastNode() { result = this.getNode(this.length() - 1) }

    /** Gets the length of this basic block. */
    int length() { result = strictcount(this.getANode()) }

    /**
     * Holds if this basic block immediately dominates basic block `bb`.
     *
     * That is, this basic block is the unique basic block satisfying:
     * 1. This basic block strictly dominates `bb`
     * 2. There exists no other basic block that is strictly dominated by this
     *    basic block and which strictly dominates `bb`.
     *
     * All basic blocks, except entry basic blocks, have a unique immediate
     * dominator.
     */
    predicate immediatelyDominates(BasicBlock bb) { bbIDominates(this, bb) }

    /**
     * Holds if this basic block strictly dominates basic block `bb`.
     *
     * That is, all paths reaching `bb` from the entry point basic block must
     * go through this basic block and this basic block is different from `bb`.
     */
    predicate strictlyDominates(BasicBlock bb) { bbIDominates+(this, bb) }

    /**
     * Holds if this basic block dominates basic block `bb`.
     *
     * That is, all paths reaching `bb` from the entry point basic block must
     * go through this basic block.
     */
    predicate dominates(BasicBlock bb) {
      bb = this or
      this.strictlyDominates(bb)
    }

    /**
     * Holds if `df` is in the dominance frontier of this basic block. That is,
     * this basic block dominates a predecessor of `df`, but does not dominate
     * `df` itself. I.e., it is equivaluent to:
     * ```
     * this.dominates(df.getAPredecessor()) and not this.strictlyDominates(df)
     * ```
     */
    predicate inDominanceFrontier(BasicBlock df) {
      // Algorithm from Cooper et al., "A Simple, Fast Dominance Algorithm" (Figure 5),
      // who in turn attribute it to Ferrante et al., "The program dependence graph and
      // its use in optimization".
      this = df.getAPredecessor() and not bbIDominates(this, df)
      or
      exists(BasicBlock prev | prev.inDominanceFrontier(df) |
        bbIDominates(this, prev) and
        not bbIDominates(this, df)
      )
    }

    /**
     * Gets the basic block that immediately dominates this basic block, if any.
     *
     * That is, the result is the unique basic block satisfying:
     * 1. The result strictly dominates this basic block.
     * 2. There exists no other basic block that is strictly dominated by the
     *    result and which strictly dominates this basic block.
     *
     * All basic blocks, except entry basic blocks, have a unique immediate
     * dominator.
     */
    BasicBlock getImmediateDominator() { bbIDominates(result, this) }

    /**
     * Holds if the edge with successor type `s` out of this basic block is a
     * dominating edge for `dominated`.
     *
     * That is, all paths reaching `dominated` from the entry point basic
     * block must go through the `s` edge out of this basic block.
     *
     * Edge dominance is similar to node dominance except it concerns edges
     * instead of nodes: A basic block is dominated by a _basic block_ `bb` if
     * it can only be reached through `bb` and dominated by an _edge_ `e` if it
     * can only be reached through `e`.
     *
     * Note that where all basic blocks (except the entry basic block) are
     * strictly dominated by at least one basic block, a basic block may not be
     * dominated by any edge. If an edge dominates a basic block `bb`, then
     * both endpoints of the edge dominates `bb`. The converse is not the case,
     * as there may be multiple paths between the endpoints with none of them
     * dominating.
     */
    predicate edgeDominates(BasicBlock dominated, SuccessorType s) {
      // For this block to control the block `dominated` with `s` the following must be true:
      // 1/ Execution must have passed through the test i.e. `this` must strictly dominate `dominated`.
      // 2/ Execution must have passed through the `s` edge leaving `this`.
      //
      // Although "passed through the `s` edge" implies that `this.getASuccessor(s)` dominates `dominated`,
      // the reverse is not true, as flow may have passed through another edge to get to `this.getASuccessor(s)`
      // so we need to assert that `this.getASuccessor(s)` dominates `dominated` *and* that
      // all predecessors of `this.getASuccessor(s)` are either `this` or dominated by `this.getASuccessor(s)`.
      //
      // For example, in the following C# snippet:
      // ```csharp
      // if (x)
      //   dominated;
      // false_successor;
      // uncontrolled;
      // ```
      // `false_successor` dominates `uncontrolled`, but not all of its predecessors are `this` (`if (x)`)
      //  or dominated by itself. Whereas in the following code:
      // ```csharp
      // if (x)
      //   while (dominated)
      //     also_controlled;
      // false_successor;
      // uncontrolled;
      // ```
      // the block `while dominated` is dominated because all of its predecessors are `this` (`if (x)`)
      // or (in the case of `also_controlled`) dominated by itself.
      //
      // The additional constraint on the predecessors of the test successor implies
      // that `this` strictly dominates `dominated` so that isn't necessary to check
      // directly.
      exists(BasicBlock succ |
        succ = this.getASuccessor(s) and dominatingEdge(this, succ) and succ.dominates(dominated)
      )
    }

    /**
     * Holds if this basic block strictly post-dominates basic block `bb`.
     *
     * That is, all paths reaching a normal exit point basic block from basic
     * block `bb` must go through this basic block and this basic block is
     * different from `bb`.
     */
    predicate strictlyPostDominates(BasicBlock bb) { bbIPostDominates+(this, bb) }

    /**
     * Holds if this basic block post-dominates basic block `bb`.
     *
     * That is, all paths reaching a normal exit point basic block from basic
     * block `bb` must go through this basic block.
     */
    predicate postDominates(BasicBlock bb) {
      this.strictlyPostDominates(bb) or
      this = bb
    }

    /** Holds if this basic block is in a loop in the control flow graph. */
    predicate inLoop() { this.getASuccessor+() = this }

    /** Gets a textual representation of this basic block. */
    string toString() { result = this.getFirstNode().toString() }
  }

  /**
   * Holds if `bb1` has `bb2` as a direct successor and the edge between `bb1`
   * and `bb2` is a dominating edge.
   *
   * An edge `(bb1, bb2)` is dominating if there exists a basic block that can
   * only be reached from the entry block by going through `(bb1, bb2)`. This
   * implies that `(bb1, bb2)` dominates its endpoint `bb2`. I.e., `bb2` can
   * only be reached from the entry block by going via `(bb1, bb2)`.
   *
   * This is a necessary and sufficient condition for an edge to dominate some
   * block, and therefore `dominatingEdge(bb1, bb2) and bb2.dominates(bb3)`
   * means that the edge `(bb1, bb2)` dominates `bb3`.
   */
  pragma[nomagic]
  predicate dominatingEdge(BasicBlock bb1, BasicBlock bb2) {
    bb1.getASuccessor(_) = bb2 and
    bbIDominates(bb1, bb2) and
    // The above is not sufficient to ensure that `bb2` can only be reached
    // through `(bb1, bb2)`. To see why, consider this example corresponding to
    // an `if` statement without an `else` block where `A` is the basic block
    // following the `if` statement:
    // ```
    // ... --> cond --[true]--> ... --> A
    //           \                      ^
    //            ----[false]-----------
    // ```
    // Here `A` is a direct successor of `cond` along the `false` edge and it
    // is immediately dominated by `cond`, but `A` is not dominated by the
    // `false` edge since it is also possible to reach `A` via the `true`
    // edge.
    //
    // Note that the first and third conjunct implies the second. But
    // explicitly including the second conjunct leads to a better join order.
    forall(BasicBlock pred | pred = bb2.getAPredecessor() and pred != bb1 | bb2.dominates(pred))
  }

  cached
  private module Cached {
    private Node nodeGetAPredecessor(Node node, SuccessorType s) {
      nodeGetASuccessor(result, s) = node
    }

    /** Holds if this node has more than one predecessor. */
    private predicate nodeIsJoin(Node node) { strictcount(nodeGetAPredecessor(node, _)) > 1 }

    /** Holds if this node has more than one successor. */
    private predicate nodeIsBranch(Node node) { strictcount(nodeGetASuccessor(node, _)) > 1 }

    /**
     * Internal representation of basic blocks. A basic block is represented
     * by its first CFG node.
     */
    cached
    newtype TBasicBlock = TBasicBlockStart(Node cfn) { startsBB(cfn) }

    /** Holds if `cfn` starts a new basic block. */
    private predicate startsBB(Node cfn) {
      not exists(nodeGetAPredecessor(cfn, _)) and exists(nodeGetASuccessor(cfn, _))
      or
      nodeIsJoin(cfn)
      or
      nodeIsBranch(nodeGetAPredecessor(cfn, _))
      or
      // In cases such as
      //
      // ```rb
      // if x and y
      //     foo
      // else
      //     bar
      // ```
      //
      // we have a CFG that looks like
      //
      // x --false--> [false] x and y --false--> bar
      //  \                    |
      //   --true--> y --false--
      //            \
      //             --true--> [true] x and y --true--> foo
      //
      // and we want to ensure that both `foo` and `bar` start a new basic block.
      exists(nodeGetAPredecessor(cfn, any(SuccessorType s | successorTypeIsCondition(s))))
    }

    /**
     * Holds if `succ` is a control flow successor of `pred` within
     * the same basic block.
     */
    private predicate intraBBSucc(Node pred, Node succ) {
      succ = nodeGetASuccessor(pred, _) and
      not startsBB(succ)
    }

    /**
     * Holds if `bbStart` is the first node in a basic block and `cfn` is the
     * `i`th node in the same basic block.
     */
    pragma[nomagic]
    private predicate bbIndex(Node bbStart, Node cfn, int i) =
      shortestDistances(startsBB/1, intraBBSucc/2)(bbStart, cfn, i)

    cached
    Node getNode(BasicBlock bb, int pos) { bbIndex(bb.getFirstNode(), result, pos) }

    /** Holds if `bb` is an entry basic block. */
    private predicate entryBB(BasicBlock bb) { nodeIsDominanceEntry(bb.getFirstNode()) }

    cached
    predicate bbSuccessor(BasicBlock bb1, BasicBlock bb2, SuccessorType t) {
      bb2.getFirstNode() = nodeGetASuccessor(bb1.getLastNode(), t)
    }

    /**
     * Holds if the first node of basic block `succ` is a control flow
     * successor of the last node of basic block `pred`.
     */
    private predicate succBB(BasicBlock pred, BasicBlock succ) { bbSuccessor(pred, succ, _) }

    /** Holds if `dom` is an immediate dominator of `bb`. */
    cached
    predicate bbIDominates(BasicBlock dom, BasicBlock bb) =
      idominance(entryBB/1, succBB/2)(_, dom, bb)

    /** Holds if `pred` is a basic block predecessor of `succ`. */
    private predicate predBB(BasicBlock succ, BasicBlock pred) { succBB(pred, succ) }

    /** Holds if `bb` is an exit basic block that represents normal exit. */
    private predicate exitBB(BasicBlock bb) { nodeIsPostDominanceExit(bb.getANode()) }

    /** Holds if `dom` is an immediate post-dominator of `bb`. */
    cached
    predicate bbIPostDominates(BasicBlock dom, BasicBlock bb) =
      idominance(exitBB/1, predBB/2)(_, dom, bb)
  }

  private import Cached
}
