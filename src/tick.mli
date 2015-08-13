(*---------------------------------------------------------------------------
   Copyright (c) 2015 Daniel C. Bünzli. All rights reserved.
   Distributed under the BSD3 license, see license at the end of the file.
   %%NAME%% release %%VERSION%%
  ---------------------------------------------------------------------------*)

(** (Un)reliable monotonic ticks for MirageOS.

     {e Release %%VERSION%% - %%MAINTAINER%% } *)

open Rresult

(** {1 Base MirageOS signatures}

    The following signatures are assumed to be part of MirageOS's signatures. *)


(** The type for POSIX time clocks.

    [PCLOCK] provides access to POSIX calendar time. This time is
    subject to operating system calendar time adjustement and can go
    back in time, it should not be used to measure wall-clock time
    spans. *)
module type PCLOCK = sig

  (** {1:posix POSIX time} *)

  val now_d_ps : unit -> int * int64
  (** [now_d_ps ()] is [(d, ps)] representing the POSIX time occuring
      at [d] * 86'400e12 + [ps] POSIX picoseconds from the epoch
      1970-01-01 00:00:00 UTC. [ps] is in the range
      \[[0];[86_399_999_999_999_999L]\]. *)

  val period_d_ps : unit -> (int * int64) option
  (** [period_d_ps ()] is if available [Some (d, ps)] representing the
      clock's picosecond period [d] * 86'400e12 + [ps]. [ps] is in the
      range \[[0];[86_399_999_999_999_999L]\]. *)

  val current_tz_offset_s : unit -> int
  (** [current_tz_offset_s ()] is the clock's current local time zone
      offset to UTC in seconds. *)
end

(** The type for monotonic time clocks.

    [MCLOCK] provides access to monotonic wall-clock time.  This time
    increases monotonically and is not subject to operating system
    calendar time adjustment. It can only be used to measure
    wall-clock time spans in a single program run. It will not
    correctly measure time spans across {!LIFECYCLE.suspend} and
    {!LIFECYCLE.resume} events as the monotonic clock does not
    increase during these two events. *)
module type MCLOCK = sig

  (** {1:monotonic Monotonic time} *)

  type ns_span = int64
  (** The type for nanosecond precision time spans. This is an
      {e unsigned} 64-bit integer. It can measure up to approximatevely
      584 Julian years before (silently) rolling over. *)

  val elapsed_ns : unit -> ns_span
  (** [elapsed_ns ()] is the wall-clock time span elapsed since the
      beginning of the program. Note that this doesn't take into
      account time the program spends between two {!LIFECYCLE.suspend}
      and {!LIFECYCLE.resume} occurences.  *)

  val period_ns : unit -> ns_span option
  (** [period_ns ()] is if available [Some d] representing the
      clock's nanosecond period [d]. *)
end

(** The type for program life cycle events.

    [LIFECYCLE] provides the ability to watch important events
    occuring in the life time of the program. *)
module type LIFECYCLE = sig

  (** {1:events Events} *)

  type 'a event
  (** The type for life cycle events with payloads of type ['a]. *)

  type watcher
  (** The type for event watchers. *)

  val watch : 'a event -> ('a -> unit) -> watcher
  (** [watch e f] is a key-value watcher such that [f] is called whenever
      event [e] occurs. *)

  val unwatch : watcher -> unit
  (** [unwatch w] stops the watcher [w]. After that call it's callback
      is guaranteed not to be called again. *)

  val poweron : unit event
  (** [poweron] occurs shortly after the system powers up. *)

  val poweroff : unit event
  (** [poweroff] occurs shortly before the system is going to power off. *)

  val suspend : unit event
  (** [suspend] occurs shortly before the system is suspended. *)

  val resume : unit event
  (** [resume] occurs shortly after the system resumes after having been
      {!suspend}ed. *)
end

(** The type for mutable key-value stores.

    [KV] provides access to typed and named values. *)
module type KV = sig

  (** {1 Value codecs} *)

  type 'a codec = ('a -> string) * (string -> ('a, R.msg) result)
  (** The type for value codecs. An encoder and a decoder. *)

  exception Decode_error of string * R.msg
  (** The exception for key value decode errors. If [Decode (key,
      msg)] is raised it means that the store's data for [key] could
      not be decoded using the client's codec. This exception is not
      meant to be handled by programs, it indicates a configuration
      mismatch between the program and its environment. *)

  (** {1:key Keys} *)

  type 'a key
  (** The type for keys with values of type ['a]. *)

  val key : string -> 'a codec -> 'a key
  (** [key name codec] is a key with lookup name [name] and whose value
      is codec'd by [codec]. *)

  val key_name : 'a key -> string
  (** [key_name k] is [k]'s name. *)

  val key_codec : 'a key -> 'a codec
  (** [key_codec k] is [k]'s codec. *)

  val mem : 'a key -> bool
  (** [mem k] is [true] iff [k] is bound to a value of type ['a]
      in the key-value store. *)

  val find : 'a key -> 'a option
  (** [find k] is [k]'s binding in the key-value store (if any).

      @raise Decode_error in case of value decode error. *)

  val get : ?absent:'a -> 'a key -> 'a
  (** [get k] is [k]'s binding the key-value store. If [absent] is
      specified this value is returned if [k] is not bound in the store.

      @raise Invalid_argument if [k] is unbound in the key-value store
      and [absent] is not specified. TODO maybe unify that with
      Decode_error.

      @raise Decode_error in case of value decode error. *)

  val set : 'a key -> 'a option -> unit
  (** [set k v] sets the key value of [k] to [v]. *)

  (** {1:watch Watching keys} *)

  type watcher
  (** The type for key-value binding change watchers. *)

  val watch : 'a key -> ('a key -> 'a option -> unit) -> watcher
  (** [watch k f] is a key-value watcher such that whenever [key] is {!set} to
      [v], [f k v] is called. *)

  val unwatch : watcher -> unit
  (** [unwatch w] stops the watcher [w]. After that call it's callback
      is guaranteed not to be called again. *)
end

(** The type for clock ticks watchers.

    [WATCHER] provides a base signature for watching nanosecond
    precision clock ticks. *)
module type WATCHER = sig

  (** {1:watcher Tick watchers} *)

  type span_ns = int64
  (** The type for positive nanoseconds time spans. This is an {e unsigned}
      64-bit integer it can represent time spans up to approximatevley 584
      Julian years. *)

  type trigger
  (** The type for tick watcher triggers. This is the value being
      acted upon when a {{!t}watcher} sees a tick. *)

  type t
  (** The type for tick watchers. Encapsulate a delay to watch
      for and a trigger to actuate whenever the delay elapsed. *)

  val watch : delay_ns:span_ns -> trigger -> t
  (** [watch d tr] is a tick in that occurs after [d] nanoseconds and is
      watched by trigger [tr]. *)

  val unwatch : t -> unit
  (** [unwatch w] unwatches the tick in [w]. If [w] is no longer
      {!waiting} this has no effect. Otherwise [w]'s trigger is guaranteed
      not to be actuated and {!waiting}[ w] becomes [false]. *)

  val waiting : t -> bool
  (** [waiting w] is [true] iff [w]'s trigger has not been actuated yet
      or [w] was not {!unwatch}ed. *)

  val linger_ns : t -> span_ns
  (** [linger_ns w] is the number of nanoseconds during which {!waiting}[ w]
      was [true]. If [w]'s trigger was actuated then:
      {ul
      {- [linger_ns w < delay_ns w] the tick was in advance.}
      {- [linger_ns w = delay_ns w] the tick was on time.}
      {- [linger_ns w > delay_ns w] the tick was late.}} *)

  val delay_ns : t -> span_ns
  (** [delay_ns w] is [w]'s waiting delay. *)

  val trigger : t -> trigger
  (** [trigger w] is [w]'s trigger. *)

  val fold : ('a -> t -> 'a) -> 'a -> 'a
  (** [fold f acc] folds over all watchers that have {!waiting }[ t = true]. *)
end

(** The type for unreliable, monotonic, clock ticks watchers.

    [UNRELIABLE] has the following properties. Given a watcher
    [w]:
    {ul
    {- If there is no {!LIFECYCLE.suspend} event while
       {!WATCHER.waiting}[ w] is [true]. The value of
       {!WATCHER.linger_ns}[ w] is an accurate and exact wall-clock time
       span.}
    {- Watcher triggers being {{!trigger}functions} they are not
       persisted and do not survive
       a {!LIFECYCLE.poweroff} event.}}

    These properties are typically sufficient for watching small timeouts
    in protocol implementations.

    {b TODO.} Maybe this should be functorized over {!MCLOCK}. *)
module type UNRELIABLE = sig

  (** {1 Unreliable clock tick watchers} *)

  type t
  (** The type for unreliable watchers. *)

  type trigger = t -> unit
  (** The type for unreliable triggers. *)

  include WATCHER with type t := t and type trigger := trigger
end

(** {1 Ticking reliably} *)

(** The type for program suspension reliable, monotonic, clock tick
    watchers.

    [SUSPENSION_RELIABLE] has the following properties. Given
    a watcher [w]:
    {ul
    {- If there is no {!LIFECYCLE.suspend} event while
       {!WATCHER.waiting}[ w] is [true], the value of
       {!WATCHER.linger_ns}[ w] is an accurate and exact wall-clock time
       span.}
    {- If there is one or more pairs of {!LIFECYCLE.suspend} and
       {!LIFECYCLE.resume} events while {!WATCHER.waiting}[ w] is [true]
       and that the difference between the value of {!PCLOCK.now_d_ps}
       at these events provides an accurate measure of the actual wall-clock
       time span that elapsed during suspension, the value of
       {!WATCHER.linger_ns}[ w] is an accurate and exact wall-clock time
       span.

       This condition is typically satisfied if {!PCLOCK} is well synchronized
       at {!LIFECYCLE.suspend} and {!LIFECYCLE.resume} and no leap second
       occurs between these two events. The absolute value of {!PCLOCK} doesn't
       matter.}
    {- Watcher triggers being {{!trigger}functions} they are not
       persisted and do not survive
       a {!LIFECYCLE.poweroff} event.}} *)
module type SUSPENSION_RELIABLE = sig

  (** {1 Suspension reliable clock tick watchers} *)

  type t
  (** The type for suspension reliable watchers. *)

  type trigger = t -> unit
  (** The type for suspension reliable triggers. *)

  include WATCHER with type t := t and type trigger := trigger

end

(** Persistent triggers. *)
module type PERSISTENT_TRIGGER = sig

  (** {1 Triggers} *)

  type t
  (** The type for persistent triggers. *)

  val trigger : int64 -> int64 -> t -> unit
  (** [trigger d t tr] is called whenever a watcher's trigger needs to
      be triggered. [d] is the watcher's delay and [t] the actual
      lingering time. *)

  val codec : (t -> string) * (string -> (t, R.msg) result)
  (** [codec] is a byte codec for triggers. *)
end


(** The type for program poweroff reliable, monotonic, clock tick
    watchers.

    [POWEROFF_RELIABLE] has the following properties. Given
    a watcher [w]:
    {ul
    {- If there is no {!LIFECYCLE.suspend} event while
       {!WATCHER.waiting}[ w] is [true], the value of
       {!WATCHER.linger_ns}[ w] is an accurate and exact wall-clock time
       span.}
    {- If there is one or more pairs of {!LIFECYCLE.suspend} and
       {!LIFECYCLE.resume} events while {!WATCHER.waiting}[ w] is [true]
       and that the difference between the value of {!PCLOCK.now_d_ps}
       at these events provides an accurate measure of the actual wall-clock
       time span that elapsed during suspension, the value of
       {!WATCHER.linger_ns}[ w] is an accurate and exact wall-clock time
       span.

       This condition is typically satisfied if {!PCLOCK} is well synchronized
       at {!LIFECYCLE.suspend} and {!LIFECYCLE.resume} and no leap second
       occurs between these two events. The absolute value of {!PCLOCK} doesn't
       matter.}
    {- If there is one or more pairs of {!LIFECYCLE.poweroff} and
       {!LIFECYCLE.poweron} events and that the difference between
       the value of {!PCLOCK.now_d_ps} at these events provides an accurate
       measure of the actual wall-clock time span that elapsed during the
       poweroff, the value of {!WATCHER.linger_ns}[ w] is an accurate and
       exact wall-clock time span.

       This condition is typically satisfied if {!PCLOCK} is well synchronized
       at {!LIFECYCLE.poweroff} and {!LIFECYCLE.poweron} and no leap second
       occurs between these two events. The absolute value of {!PCLOCK} doesn't
       matter.}}
    In this interface triggers can be {{!PERSISTENT_TRIGGER}persisted}.
    Note that trigger actuation occurs through the {!PERSISTENT_TRIGGER}
    interface. *)
module type POWEROFF_RELIABLE = sig
  include WATCHER
end

module Make_suspension_reliable : functor
(P : PCLOCK) (M : MCLOCK) (U : UNRELIABLE) (E : LIFECYCLE) ->
  SUSPENSION_RELIABLE

module Make_poweroff_reliable : functor
(P : PCLOCK) (M : MCLOCK) (U : UNRELIABLE) (E : LIFECYCLE)
(T : PERSISTENT_TRIGGER)
(Kv : KV) -> POWEROFF_RELIABLE with type trigger = T.t

(*---------------------------------------------------------------------------
   Copyright (c) 2015 Daniel C. Bünzli.
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   1. Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.

   3. Neither the name of Daniel C. Bünzli nor the names of
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  ---------------------------------------------------------------------------*)
