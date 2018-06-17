open Base

open Components
open Escher_Core
open Exceptions
open Types

exception Success

type task = {
  target : component ;
  inputs : Vector.t list ;
  components : component list
}

let rec divide f arity target acc =
  if arity = 0 then
    if target = 0 then f acc else ()
  else begin
    for i = 1 to target do
      divide f (arity - 1) (target - i) (i::acc)
    done
  end

(* Rename to "divide" if using the "depth" heuristic, which violates our
   additivity assumption *)
let rec divide_depth f arity target acc =
  if arity = 0 then f acc
  else if arity = 1 && List.for_all ~f:(fun x -> x < target) acc
       then f (target::acc)
       else begin
         for i = 0 to target do
           divide f (arity - 1) target (i::acc)
         done
       end

let _unsupported_ = (fun l -> " **UNSUPPORTED** ")

let apply_component (c : component) (args : Vector.t list) =
  if (not (c.check List.(map ~f:(fun a -> (snd (fst a))) args)))
  then ((("", (fun _ -> VBool false)), FCall ("", [])),
        Array.map ~f:(fun _ -> VError) (snd (List.hd_exn args)))
  else (
    let select i l = List.map ~f:(fun x -> x.(i)) l in
    let prs = List.map ~f:(fun (((_,x),_),_) -> x) args in
    let values = List.map ~f:snd args in
    let new_prog = fun ars -> c.apply (List.map ~f:(fun p -> p ars) prs) in
    let new_str = c.dump (List.map ~f:(fun (((x,_),_),_) -> x) args) in
    let result = Array.mapi ~f:(fun i _ -> try c.apply (select i values) with _ -> VError) (List.hd_exn values)
    in (((new_str, new_prog), FCall (c.name, List.map ~f:(fun ((_,x),_) -> x) args)), result))

(* Upper bound on the heuristic value a solution may take *)
let max_h = ref 15

let goal_graph = ref false

let noisy = ref false
let quiet = ref true

let all_solutions = ref []
let synth_candidates = ref 0

let hvalue ((_,x),_) = program_size x

type goal_status =
  | Closed of Vector.t
  | Open

and goal = {
  varray : value array;
  mutable status : goal_status;
}

let short_goal_string goal = match goal.status with
  | Open -> "<open> " ^ (varray_string goal.varray)
  | Closed v -> "<closed> " ^ (Vector.string v)

let rec print_goal indent goal =
  if String.length indent > 10 then Stdio.print_endline (indent ^ "...")
  else Stdio.print_endline (indent ^ "goal: " ^ (varray_string goal.varray))

let solve_impl ?ast:(ast=false) task consts =
  let vector_size = Array.length (snd (List.hd_exn task.inputs)) in
  let components = task.components in

  let final_goal = { varray = snd (apply_component task.target task.inputs)
                   ; status = Open } in

  let goals = ref (VArrayMap.add final_goal.varray final_goal VArrayMap.empty) in

  let close_goal vector goal =
    if !noisy then begin
      Stdio.print_endline ("Closed goal " ^ (varray_string goal.varray));
      Stdio.print_endline ("       with " ^ (Vector.string vector));
      end else ();
    goal.status <- Closed vector;
    match final_goal.status with
    | Closed cls -> (all_solutions := cls::all_solutions.contents
                    ; if not ast then raise Success else ())
    | _ -> ()
  in

  let int_array = Array.create ~len:!max_h VSet.empty in
  let bool_array = Array.create ~len:!max_h VSet.empty in

  let check_vector v =
    (* Close all matching goals *)
    let (v_closes, _) = partition_map (varray_matches ~typeonly:ast (snd v)) (!goals)
    in if !noisy then begin
         Stdio.print_endline "--- new vector --------------------------------------";
         Stdio.print_endline ((Int.to_string (hvalue v)) ^ ": " ^ (Vector.string v));
       end else ();
       synth_candidates := 1 + (!synth_candidates);
       List.iter ~f:(close_goal v) v_closes; true
  in

  let int_components = List.filter ~f:(fun c -> Poly.equal c.codomain TInt) components in
  let bool_components = List.filter ~f:(fun c -> Poly.equal c.codomain TBool) components in

  let apply_comp f types i =
    let rec apply_cells types acc locations = match types, locations with
      | (typ::typs, i::locs) -> VSet.iter (fun x -> apply_cells typs (x::acc) locs) begin
          match typ with
            | TInt -> int_array.(i)
            | TBool -> bool_array.(i)
            | _ -> raise (Invalid_Type_Exn ("Escher does not handle type: "
                                           ^ (string_of_typ typ)))
          end
      | ([], []) -> f (List.rev acc)
      | _ -> failwith "Impossible!"
    in divide (apply_cells types []) (List.length types) (i-1) []
  in
  let expand_component c array i =
    let f x =
      let vector = apply_component c x in
      let h_value = hvalue vector in
      let has_err = Array.fold ~f:(fun p x -> match x with VError -> true | _ -> p) ~init:false (snd vector) in
      if (h_value < !max_h && (not has_err))
      then ((if not (!noisy) then ()
            else Stdio.print_endline (Int.to_string h_value ^ ">>" ^ (Vector.string vector)));
            array.(h_value) <- VSet.add vector (array.(h_value)))
    in apply_comp f c.domain i
  in
  let expand_type (mat, components) i =
    List.iter ~f:(fun c -> expand_component c mat i) components;
  in
  let expand i =
    List.iter ~f:(fun x -> expand_type x i) [(int_array, int_components); (bool_array, bool_components)]
  in
  let btrue = let vtrue = Th_Bool.vtrue
              in ((("true", (fun ars -> vtrue)), Const vtrue), Array.create ~len:vector_size vtrue) in
  let bfalse = let vfalse = Th_Bool.vfalse
               in ((("false", (fun ars -> vfalse)), Const vfalse), Array.create ~len:vector_size vfalse) in
  let bzero = let vzero = Th_LIA.vzero
              in ((("0", (fun ars -> vzero)), Const vzero), Array.create ~len:vector_size vzero) in
  let bone = let vone = Th_LIA.vone
             in ((("1", (fun ars -> vone)), Const vone), Array.create ~len:vector_size vone) in
  if !quiet then () else (
    Stdio.print_endline ("Inputs: ");
    List.iter ~f:(fun v -> Stdio.print_endline ("   " ^ (Vector.string v))) task.inputs;
    Stdio.print_endline ("Goal: " ^ (varray_string final_goal.varray)));
    (*TODO: Only handles string and int constants, extend for others*)
  int_array.(1)
    <- List.fold ~f:(fun p i -> let vi = VInt i
                                in VSet.add ((((Int.to_string i), (fun ars -> vi)), Const vi),
                                             Array.create ~len:vector_size vi) p)
                 ~init:(VSet.add bone (VSet.singleton bzero))
                 (List.dedup_and_sort ~compare (List.filter_map consts ~f:(function VInt x -> Some (abs x)
                                                                                  | _ -> None)));
  bool_array.(1) <- VSet.add btrue (VSet.singleton bfalse);
  List.iter ~f:(fun input ->
    let array = match (snd input).(1) with
      | VInt _ -> int_array
      | VBool _ -> bool_array
      | VError -> failwith "Error in input"
      | VDontCare -> failwith "Underspecified input"
    in array.(1) <- VSet.add input array.(1))
  task.inputs;
  for i = 2 to !max_h-1; do
    int_array.(i-1) <- VSet.filter check_vector int_array.(i-1);
    bool_array.(i-1) <- VSet.filter check_vector bool_array.(i-1);
    begin match final_goal.status with
      | Closed p -> final_goal.status <- Open
      | Open -> () end;
    (*(if !quiet then prerr_string else print_endline) (" @" ^ (string_of_int i)); flush_all();*)
    if !noisy then begin
      let print_goal k _ = Stdio.print_endline (" * " ^ (varray_string k)) in
        Stdio.print_endline ("Goals: ");
        VArrayMap.iter print_goal (!goals);
    end else ();
    expand i;
  done

let solve ?(ast = false) task consts =
  all_solutions := [] ; synth_candidates := 0;
  (try solve_impl ~ast:ast task consts with Success -> ());
  if not (!quiet) then (
    Stdio.print_endline "Synthesis Result: ";
    List.iter ~f:(fun v -> Stdio.print_endline (Vector.string v)) all_solutions.contents
  ) ; List.rev_map all_solutions.contents
                   ~f:(fun (((dump, func), program), outputs) -> (dump, func))

let components_for (l : logic) : component list =
  match l with
  | LLIA -> Th_LIA.all_components
  | LNIA -> Th_NIA.all_components