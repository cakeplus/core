(** purely functional command line parsing *)

open Core_kernel.Std

(** {1 argument types} *)
module Arg_type : sig
  type 'a t (** the type of a command line argument *)

  (** An argument type includes information about how to parse values of that type from
      the command line, and (optionally) how to auto-complete partial arguments of that
      type via bash's programmable TAB-completion.  In addition to the argument prefix,
      autocompletion also has access to any previously parsed arguments in the form of a
      heterogeneous map into which previously parsed arguments may register themselves by
      providing a [Univ_map.Key] using the [~key] argument to [create].

      If the [of_string] function raises an exception, command line parsing will be
      aborted and the exception propagated up to top-level and printed along with
      command-line help. *)
  val create
    :  ?complete:(Univ_map.t -> part:string -> string list)
    -> ?key:'a Univ_map.Multi.Key.t
    -> (string -> 'a)
    -> 'a t

  (** an auto-completing Arg_type over a finite set of values *)
  val of_map : ?key:'a Univ_map.Multi.Key.t -> 'a String.Map.t -> 'a t

  (** convenience wrapper for [of_map].  Raises on duplicate keys *)
  val of_alist_exn : ?key:'a Univ_map.Multi.Key.t -> (string * 'a) list -> 'a t

  (** [file] defines an [Arg_type.t] that completes in the same way as
      [Command.Spec.file], but perhaps with a different type than [string] or with an
      autocompletion key. *)
  val file
    :  ?key:'a Univ_map.Multi.Key.t
    -> (string -> 'a)
    -> 'a t

  (* values to include in other namespaces *)
  module Export : sig

    val string             : string             t
    (** Beware that an anonymous argument of type [int] cannot be specified as negative,
        as it is ambiguous whether -1 is a negative number or a flag. If you need to pass
        a negative number to your program, make it a parameter to a flag. *)
    val int                : int                t
    val char               : char               t
    val float              : float              t
    val bool               : bool               t
    val date               : Date.t             t
    (** [time] requires a time zone. *)
    val time               : Time.t             t
    val time_ofday         : Time.Ofday.Zoned.t t
    (** Use [time_ofday_unzoned] only when time zone is implied somehow. *)
    val time_ofday_unzoned : Time.Ofday.t       t
    val time_span          : Time.Span.t        t
    (* [file] uses bash autocompletion. *)
    val file               : string             t
  end
end

(** {1 flag specifications} *)
module Flag : sig
  type 'a t

  (** required flags must be passed exactly once *)
  val required : 'a Arg_type.t -> 'a t

  (** optional flags may be passed at most once *)
  val optional : 'a Arg_type.t -> 'a option t

  (** [optional_with_default] flags may be passed at most once, and
      default to a given value *)
  val optional_with_default : 'a -> 'a Arg_type.t -> 'a t

  (** [listed] flags may be passed zero or more times *)
  val listed : 'a Arg_type.t -> 'a list t

  (** [one_or_more] flags must be passed one or more times *)
  val one_or_more : 'a Arg_type.t -> ('a * 'a list) t

  (** [no_arg] flags may be passed at most once.  The boolean returned
      is true iff the flag is passed on the command line *)
  val no_arg : bool t

  (** [no_arg_register ~key ~value] is like [no_arg], but associates [value]
      with [key] in the in the auto-completion environment *)
  val no_arg_register : key:'a Univ_map.With_default.Key.t -> value:'a -> bool t

  (** [no_arg_abort ~exit] is like [no_arg], but aborts command-line parsing
      by calling [exit].  This flag type is useful for "help"-style flags that
      just print something and exit. *)
  val no_arg_abort : exit:(unit -> never_returns) -> unit t

  (** [escape] flags may be passed at most once.  They cause the command line parser to
      abort and pass through all remaining command line arguments as the value of the
      flag.

      A standard choice of flag name to use with [escape] is ["--"]. *)
  val escape : string list option t
end

(** {1 anonymous argument specifications} *)
module Anons : sig

  type 'a t (** a specification of some number of anonymous arguments *)

  (** [(name %: typ)] specifies a required anonymous argument of type [typ].

      The [name] must not be surrounded by whitespace, if it is, an exn will be raised.

      If the [name] is surrounded by a special character pair (<>, \{\}, \[\] or (),)
      [name] will remain as-is, otherwise, [name] will be uppercased.

      In the situation where [name] is only prefixed or only suffixed by one of the
      special character pairs, or different pairs are used, (e.g. "<ARG\]") an exn will
      be raised.

      The (possibly transformed) [name] is mentioned in the generated help for the
      command. *)
  val ( %: ) : string -> 'a Arg_type.t -> 'a t

  (** [sequence anons] specifies a sequence of anonymous arguments.  An exception
      will be raised if [anons] matches anything other than a fixed number of
      anonymous arguments  *)
  val sequence : 'a t -> 'a list t

  (** [non_empty_sequence anons] is like [sequence anons] except an exception will be
      raised if there is not at least one anonymous argument given. *)
  val non_empty_sequence : 'a t -> ('a * 'a list) t

  (** [(maybe anons)] indicates that some anonymous arguments are optional *)
  val maybe : 'a t -> 'a option t

  (** [(maybe_with_default default anons)] indicates an optional anonymous
      argument with a default value *)
  val maybe_with_default : 'a -> 'a t -> 'a t

  (** [t2], [t3], and [t4] each concatenate multiple anonymous argument
      specs into a single one. The purpose of these combinators is to allow
      for optional sequences of anonymous arguments.  Consider a command with
      usage:

      {v
        main.exe FOO [BAR BAZ]
       v}

      where the second and third anonymous arguments must either both
      be there or both not be there.  This can be expressed as:

      {[
        t2 ("FOO" %: foo) (maybe (t2 ("BAR" %: bar) ("BAZ" %: baz)))]
       ]}

      Sequences of 5 or more anonymous arguments can be built up using
      nested tuples:

      {[
        maybe (t3 a b (t3 c d e))
      ]}
  *)

  val t2 : 'a t -> 'b t -> ('a * 'b) t

  val t3 : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t

  val t4 : 'a t -> 'b t -> 'c t -> 'd t -> ('a * 'b * 'c * 'd) t
end

(** {1 specification of command parameters} *)
module Param : sig
  module type S = sig
    include Applicative.S

    (** {2 various internal values} *)

    val help : string Lazy.t t (** the help text for the command *)
    val path : string list   t (** the subcommand path of the command *)
    val args : string list   t (** the arguments passed to the command *)

    (** [flag name spec ~doc] specifies a command that, among other things, takes a flag
        named [name] on its command line.  [doc] indicates the meaning of the flag.

        All flags must have a dash at the beginning of the name.  If [name] is not prefixed
        by "-", it will be normalized to ["-" ^ name].

        Unless [full_flag_required] is used, one doesn't have to pass [name] exactly on the
        command line, but only an unambiguous prefix of [name] (i.e., a prefix which is not
        a prefix of any other flag's name).

        NOTE: the [doc] for a flag which takes an argument should be of the form
        [arg_name ^ " " ^ description] where [arg_name] describes the argument and
        [description] describes the meaning of the flag.

        NOTE: flag names (including aliases) containing underscores will be rejected.
        Use dashes instead.

        NOTE: "-" by itself is an invalid flag name and will be rejected.
    *)
    val flag
      :  ?aliases            : string list
      -> ?full_flag_required : unit
      -> string
      -> 'a Flag.t
      -> doc : string
      -> 'a t

    (** [anon spec] specifies a command that, among other things, takes the anonymous
        arguments specified by [spec]. *)
    val anon : 'a Anons.t -> 'a t
  end

  include S

  (* values included for convenience so you can specify all command line parameters inside
     a single local open of [Param] *)

  module Args : Applicative.Args with type 'a arg := 'a t
  include module type of Args with type ('a, 'b) t := ('a, 'b) Args.t

  module Arg_type : module type of Arg_type with type 'a t = 'a Arg_type.t
  include module type of Arg_type.Export
  include module type of Flag  with type 'a t := 'a Flag.t
  include module type of Anons with type 'a t := 'a Anons.t
end

(** {1 older interface for command-line specifications} *)
module Spec : sig

  (** {1 command parameters} *)

  (** specification of an individual parameter to the command's main function *)
  type 'a param = 'a Param.t
  include Param.S with type 'a t := 'a param

  (** Superceded by [return], preserved for backwards compatibility *)
  val const : 'a -> 'a param

  (** Superceded by [both], preserved for backwards compatibility *)
  val pair : 'a param -> 'b param -> ('a * 'b) param

  (** {1 command specifications} *)

  (** composable command-line specifications *)
  type ('main_in, 'main_out) t
  (**
      Ultimately one forms a basic command by combining a spec of type
      [('main, unit -> unit) t] with a main function of type ['main]; see the [basic]
      function below.  Combinators in this library incrementally build up the type of main
      according to what command-line parameters it expects, so the resulting type of
      [main] is something like:

      [arg1 -> ... -> argN -> unit -> unit]

      It may help to think of [('a, 'b) t] as a function space ['a -> 'b] embellished with
      information about:

      {ul {- how to parse command line}
          {- what the command does and how to call it}
          {- how to auto-complete a partial command line}}

      One can view a value of type [('main_in, 'main_out) t] as function that transforms a
      main function from type ['main_in] to ['main_out], typically by supplying some
      arguments.  E.g. a value of type [Spec.t] might have type:

      {[
        (arg1 -> ... -> argN -> 'r, 'r) Spec.t
      ]}

      Such a value can transform a main function of type [arg1 -> ... -> argN -> 'r] by
      supplying it argument values of type [arg1], ..., [argn], leaving a main function
      whose type is ['r].  In the end, [Command.basic] takes a completed spec where
      ['r = unit -> unit], and hence whose type looks like:

      {[
        (arg1 -> ... -> argN -> unit -> unit, unit -> unit) Spec.t
      ]}

      A value of this type can fully apply a main function of type
      [arg1 -> ... -> argN -> unit -> unit] to all its arguments.

      The final unit argument allows the implementation to distinguish between the phases
      of (1) parsing the command line and (2) running the body of the command.  Exceptions
      raised in phase (1) lead to a help message being displayed alongside the exception.
      Exceptions raised in phase (2) are displayed without any command line help.

      The view of [('main_in, main_out) Spec.t] as a function from ['main_in] to
      ['main_out] is directly reflected by the [step] function, whose type is:

      {[
        val step : ('m1 -> 'm2) -> ('m1, 'm2) t
      ]}
  *)

  (** [spec1 ++ spec2 ++ ... ++ specN] composes spec1 through specN.

      For example, if [spec_a] and [spec_b] have types:

      {[
        spec_a: (a1 -> ... -> aN -> 'ra, 'ra) Spec.t
        spec_b: (b1 -> ... -> bM -> 'rb, 'rb) Spec.t
      ]}

      then [spec_a ++ spec_b] has the following type:

      {[
        (a1 -> ... -> aN -> b1 -> ... -> bM -> 'rb, 'rb) Spec.t
      ]}

      So, [spec_a ++ spec_b] transforms a main function it by first supplying [spec_a]'s
      arguments of type [a1], ..., [aN], and then supplying [spec_b]'s arguments of type
      [b1], ..., [bm].

      One can understand [++] as function composition by thinking of the type of specs
      as concrete function types, representing the transformation of a main function:

      {[
        spec_a: \/ra. (a1 -> ... -> aN -> 'ra) -> 'ra
        spec_b: \/rb. (b1 -> ... -> bM -> 'rb) -> 'rb
      ]}

      Under this interpretation, the composition of [spec_a] and [spec_b] has type:

      {[
        spec_a ++ spec_b : \/rc. (a1 -> ... -> aN -> b1 -> ... -> bM -> 'rc) -> 'rc
      ]}

      And the implementation is just function composition:

      {[
        sa ++ sb = fun main -> sb (sa main)
      ]}
  *)

  (** the empty command-line spec *)
  val empty : ('m, 'm) t

  (** command-line spec composition *)
  val (++) : ('m1, 'm2) t -> ('m2, 'm3) t -> ('m1, 'm3) t

  (** add a rightmost parameter onto the type of main *)
  val (+>) : ('m1, 'a -> 'm2) t -> 'a param -> ('m1, 'm2) t

  (** add a leftmost parameter onto the type of main *)
  val (+<) : ('m1, 'm2) t -> 'a param -> ('a -> 'm1, 'm2) t
    (** this function should only be used as a workaround in situations where the
        order of composition is at odds with the order of anonymous arguments due
        to factoring out some common spec *)

  (** combinator for patching up how parameters are obtained or presented *)
  val step : ('m1 -> 'm2) -> ('m1, 'm2) t
  (** Here are a couple examples of some of its many uses
      {ul
        {li {i introducing labeled arguments}
            {v step (fun m v -> m ~foo:v)
               +> flag "-foo" no_arg : (foo:bool -> 'm, 'm) t v}}
        {li {i prompting for missing values}
            {v step (fun m user -> match user with
                 | Some user -> m user
                 | None -> print_string "enter username: "; m (read_line ()))
               +> flag "-user" (optional string) ~doc:"USER to frobnicate"
               : (string -> 'm, 'm) t v}}
      }

      A use of [step] might look something like:

      {[
        step (fun main -> let ... in main x1 ... xN) : (arg1 -> ... -> argN -> 'r, 'r) t
      ]}

      Thus, [step] allows one to write arbitrary code to decide how to transform a main
      function.  As a simple example:

      {[
        step (fun main -> main 13.) : (float -> 'r, 'r) t
      ]}

      This spec is identical to [const 13.]; it transforms a main function by supplying
      it with a single float argument, [13.].  As another example:

      {[
        step (fun m v -> m ~foo:v) : (foo:'foo -> 'r, 'foo -> 'r) t
      ]}

      This spec transforms a main function that requires a labeled argument into
      a main function that requires the argument unlabeled, making it easily composable
      with other spec combinators. *)

  (** combinator for defining a class of commands with common behavior *)
  val wrap : (run:('m1 -> 'r1) -> main:'m2 -> 'r2) -> ('m1, 'r1) t -> ('m2, 'r2) t
  (** Here are two examples of command classes defined using [wrap]
      {ul
        {li {i print top-level exceptions to stderr}
            {v wrap (fun ~run ~main ->
                 Exn.handle_uncaught ~exit:true (fun () -> run main)
               ) : ('m, unit) t -> ('m, unit) t
             v}}
        {li {i iterate over lines from stdin}
            {v wrap (fun ~run ~main ->
                 In_channel.iter_lines stdin ~f:(fun line -> run (main line))
               ) : ('m, unit) t -> (string -> 'm, unit) t
             v}}
      }
  *)

  val of_params : ('a, 'b) Param.Args.t -> ('a, 'b) t

  module Arg_type : module type of Arg_type with type 'a t = 'a Arg_type.t

  include module type of Arg_type.Export


  type 'a flag = 'a Flag.t (** a flag specification *)
  include module type of Flag with type 'a t := 'a flag

  (** [map_flag flag ~f] transforms the parsed result of [flag] by applying [f] *)
  val map_flag : 'a flag -> f:('a -> 'b) -> 'b flag

  (** [flags_of_args_exn args] creates a spec from [Caml.Arg.t]s, for compatibility with
      ocaml's base libraries.  Fails if it encounters an arg that cannot be converted.

      NOTE: There is a difference in side effect ordering between [Caml.Arg] and
      [Command].  In the [Arg] module, flag handling functions embedded in [Caml.Arg.t]
      values will be run in the order that flags are passed on the command line.  In the
      [Command] module, using [flags_of_args_exn flags], they are evaluated in the order
      that the [Caml.Arg.t] values appear in [flags].
  *)
  val flags_of_args_exn : Core_kernel.Std.Arg.t list -> ('a, 'a) t

  type 'a anons = 'a Anons.t (** a specification of some number of anonymous arguments *)
  include module type of Anons with type 'a t := 'a anons

  (** [map_anons anons ~f] transforms the parsed result of [anons] by applying [f] *)
  val map_anons : 'a anons -> f:('a -> 'b) -> 'b anons
end

type t (** commands which can be combined into a hierarchy of subcommands *)

type ('main, 'result) basic_command
  =  summary : string
  -> ?readme : (unit -> string)
  -> ('main, unit -> 'result) Spec.t
  -> 'main
  -> t

(** [basic ~summary ?readme spec main] is a basic command that executes a function [main]
    which is passed parameters parsed from the command line according to [spec].
    [summary] is to contain a short one-line description of its behavior.  [readme] is to
    contain any longer description of its behavior that will go on that commands' help
    screen. *)
val basic : ('main, unit) basic_command

type ('main, 'result) basic_command'
  =  summary : string
  -> ?readme : (unit -> string)
  -> ('main, unit -> 'result) Param.Args.t
  -> 'main
  -> t

(** Same general behavior as [basic], but takes a command line specification built up
    using [Params] instead of [Spec]. *)
val basic' : ('main, unit) basic_command'

(** [group ~summary subcommand_alist] is a compound command with named
    subcommands, as found in [subcommand_alist].  [summary] is to contain
    a short one-line description of the command group.  [readme] is to
    contain any longer description of its behavior that will go on that
    command's help screen.

    NOTE: subcommand names containing underscores will be rejected.  Use dashes
    instead.

    [body] is called when no additional arguments are passed -- in particular, when no
    subcommand is passed.  Its [path] argument is the subcommand path by which the group
    command was reached. *)
val group
  :  summary                    : string
  -> ?readme                    : (unit -> string)
  -> ?preserve_subcommand_order : unit
  -> ?body                      : (path:string list -> unit)
  -> (string * t) list
  -> t

(** [exec ~summary ~path_to_exe] runs [exec] on the executable at [path_to_exe]. If
    [path_to_exe] is [`Absolute path] then [path] is executed without any further
    qualification.  If it is [`Relative_to_me path] then [Filename.dirname
    Sys.executable_name ^ "/" ^ path] is executed instead.  All of the usual caveats about
    [Sys.executable_name] apply: specifically, it may only return an absolute path in
    Linux.  On other operating systems it will return [Sys.argv.(0)].

    Care has been taken to support nesting multiple executables built with Command.  In
    particular, recursive help and autocompletion should work as expected.

    NOTE: non-Command executables can be used with this function but will still be
    executed when [help -recursive] is called or autocompletion is attempted (despite the
    fact that neither will be particularly helpful in this case).  This means that if you
    have a shell script called "reboot-everything.sh" that takes no arguments and reboots
    everything no matter how it is called, you shouldn't use it with [exec].

    Additionally, no loop detection is attempted, so if you nest an executable within
    itself, [help -recursive] and autocompletion will hang forever (although actually
    running the subcommand will work). *)
val exec
  :  summary     : string
  -> ?readme     : (unit -> string)
  -> path_to_exe : [ `Absolute of string | `Relative_to_me of string ]
  -> unit
  -> t

(** extract the summary string for a command *)
val summary : t -> string

module Shape : sig
  type command
  type t =
    | Basic
    | Group of (string * command) list
    | Exec of (unit -> t)
end
with type command := t

(** expose the shape of a command *)
val shape : t -> Shape.t

(** Run a command against [Sys.argv], or [argv] if it is specified.

    [extend] can be used to add extra command line arguments to basic subcommands of the
    command.  [extend] will be passed the (fully expanded) path to a command, and its
    output will be appended to the list of arguments being processed.  For example,
    suppose a program like this is compiled into [exe]:

      {[
        let bar = Command.basic ...
        let foo = Command.group ~summary:... ["bar", bar]
        let main = Command.group ~summary:... ["foo", foo]
        Command.run ~extend:(fun _ -> ["-baz"]) main
      ]}

    Then if a user ran [exe f b], [extend] would be passed [["foo"; "bar"]] and ["-baz"]
    would be appended to the command line for processing by [bar].  This can be used to
    add a default flags section to a user config file.
*)
val run
  :  ?version    : string
  -> ?build_info : string
  -> ?argv       : string list
  -> ?extend     : (string list -> string list)
  -> t
  -> unit

(** [Deprecated] should be used only by [Core_extended.Deprecated_command].  At some point
    it will go away. *)
module Deprecated : sig
  module Spec : sig
    val no_arg : hook:(unit -> unit) -> bool Spec.flag
    val escape : hook:(string list -> unit) -> string list option Spec.flag
    val ad_hoc : usage_arg:string -> string list Spec.anons
  end

  val summary : t -> string

  val help_recursive
    :  cmd         : string
    -> with_flags  : bool
    -> expand_dots : bool
    -> t
    -> string
    -> (string * string) list

  val run
    :  t
    -> cmd               : string
    -> args              : string list
    -> is_help           : bool
    -> is_help_rec       : bool
    -> is_help_rec_flags : bool
    -> is_expand_dots    : bool
    -> unit

  val get_flag_names : t ->  string list
  val version : string
  val build_info : string
end
