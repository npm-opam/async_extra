(** An [Mvar] is a mutable location that is either empty or contains a value.  One can
    [put] or [set] the value, and wait on [value_available] for the location to be filled
    in either way.

    Having an [Mvar.Writer.t] gives the capability to mutate the mvar.

    The key difference between an [Mvar] and an [Ivar] is that an [Mvar] may be filled
    multiple times.

    This implementation of [Mvar] also allows one to replace the value without any
    guarantee that the reading side has seen it.  This is useful in situations where
    last-value semantics are desired (i.e. you want to signal whenever a config file is
    updated, but only care about the most recent values).

    A [Mvar] can also be used as a baton passing mechanism between a producer
    and consumer.  For instance, a producer reading from a socket and producing
    a set of deserialized messages can put the batch from a single read into an
    [Mvar] and can wait for [taken] to return as a pushback mechanism.  The
    consumer meanwhile waits on [value_available].  This way the natural batch
    size is passed between the two sub-systems with minimal overhead. *)

open! Core.Std
open! Import

type ('a, 'phantom) t [@@deriving sexp_of]

module Read_write : sig
  type nonrec 'a t = ('a, read_write) t [@@deriving sexp_of]

  include Invariant.S1 with type 'a t := 'a t
end

module Read_only : sig
  type nonrec 'a t = ('a, read) t [@@deriving sexp_of]

  include Invariant.S1 with type 'a t := 'a t
end

val create : unit -> 'a Read_write.t

val is_empty : (_, _) t -> bool

(** [put t a] waits until [is_empty t], and then does [set t a].  If there are multiple
    concurrent [put]s, there is no fairness guarantee (i.e. [put]s may happen out of order
    or may be starved). *)
val put : 'a Read_write.t -> 'a -> unit Deferred.t

(** [set t a] sets the value in [t] to [a], even if [not (is_empty t)].  This is useful if
    you want takers to have last-value semantics. *)
val set : 'a Read_write.t -> 'a -> unit

val read_only : 'a Read_write.t -> 'a Read_only.t

(** [value_available t] returns a deferred [d] that becomes determined when a value is in
    [t].  [d] does not include the value in [t] because that value may change after [d]
    becomes determined and before a deferred bind on [d] gets to run.

    Repeated calls to [value_available] will always return the same deferred until [take]
    returns [Some]. *)
val value_available : _ Read_only.t -> unit Deferred.t

(** [take t] returns the value in [t] and clears [t], or returns [None] if [is_empty t].
    [take_exn] is like [take], except it raises if [is_empty t]. *)
val take     : 'a Read_only.t -> 'a option
val take_exn : 'a Read_only.t -> 'a

(** [taken t] returns a deferred that is filled the next time [take] clears [t]. *)
val taken : (_, _) t -> unit Deferred.t

(** [peek t] returns the value in [t] without clearing [t], or returns [None] is [is_empty
    t].  [peek_exn t] is like [peek], except it raises if [is_empty t]. *)
val peek     : ('a, _) t -> 'a option
val peek_exn : ('a, _) t -> 'a
