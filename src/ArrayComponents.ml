open Base

open Expr

let all = [
  {
    name = "select";
    codomain = Type.TVAR ("'b");
    domain = [Type.ARRAY (Type.TVAR "'a", Type.TVAR "'b"); Type.TVAR "'a"];
    is_argument_valid = (function
                         | _ -> true);
    evaluate = (function [@warning "-8"]
                [Value.Array (_, _, elems, default_val) ; key]
                -> match List.Assoc.find elems ~equal:Value.equal key with
                   | None -> default_val
                   | Some value -> value);
    to_string = (fun [@warning "-8"] [a ; b] -> "(select " ^ a ^ " " ^ b ^ ")");
    global_constraints = (fun _ -> [])
  }
  ;
  {
    name = "store";
    codomain = Type.ARRAY (Type.TVAR "'a", Type.TVAR "'b");
    domain = [Type.ARRAY (Type.TVAR "'a", Type.TVAR "'b"); Type.TVAR "'a"; Type.TVAR "'b"];
    is_argument_valid = (function
                         | _ -> true);
    evaluate = (function [@warning "-8"]
                [Value.Array (key_type, val_type, elems, default_val) ; key; value]
                -> Value.Array (key_type,val_type, (key, value)::elems,default_val));
    to_string = (fun [@warning "-8"] [a ; b ; c] -> "(store " ^ a ^ " " ^ b ^ " " ^ c ^ ")");
    global_constraints = (fun _ -> [])
  }

]
