val sql_count : int ref
val connect_count : int ref
val query : string -> string list -> Carolina.row list
val disconnect : unit -> unit
