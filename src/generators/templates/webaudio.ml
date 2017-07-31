
open GenerateParams

let performFunctionCall module_name (config:configuration) =
   (* generates the aguments for the process call *)
   let args =
      List.mapi (fun i _ -> [%pla{|in_<#i#i>[n]|}]) config.process_inputs
      |> (fun a -> if config.pass_data then (Pla.string "processor.context")::a else a)
      |> (fun a -> if List.length config.process_outputs > 1 then a@[Pla.string "ret"] else a)
      |> Pla.join_sep Pla.comma
   in
   (* declares the return variable and copies the values to the output buffers *)
   let copy =
      match config.process_outputs with
      | []  -> Pla.unit
      | [_] ->
         let value = Pla.string "ret" in
         [%pla{|out_0[n] = <#value#>;|}]
      | o ->
         List.mapi
            (fun i _ ->
                let value = [%pla{|ret.field_<#i#i>|}] in
                [%pla{|out_<#i#i>[n] = <#value#>;|}]) o
         |> Pla.join_sep_all Pla.newline
   in
   [%pla{|for (var n = 0; n < e.inputBuffer.length; n++) {
          var ret = processor.<#module_name#s>_process(<#args#>);<#><#copy#> <#>}|}]

let noteFunctions (params:params) =
   let module_name = params.module_name in
   let on_args =
      ["note"; "velocity"; "channel"]
      |> (fun a -> if params.config.pass_data then "processor.context"::a else a)
      |> Pla.map_sep Pla.comma Pla.string
   in
   let off_args =
      ["note"; "channel"]
      |> (fun a -> if params.config.pass_data then "processor.context"::a else a)
      |> Pla.map_sep Pla.comma Pla.string
   in
   [%pla{|
   node.noteOn = function(note, velocity, channel){
      if(velocity > 0) processor.<#module_name#s>_noteOn(<#on_args#>);
      else processor.<#module_name#s>_noteOff(<#off_args#>);
   }|}],
   [%pla{|
   node.noteOff = function(note, channel) {
      processor.<#module_name#s>_noteOff(<#off_args#>);
   }|}]

let controlChangeFunction (params:params) =
   let module_name = params.module_name in
   let ctrl_args =
      ["control"; "value"; "channel"]
      |> (fun a -> if params.config.pass_data then "processor.context"::a else a)
      |> Pla.map_sep Pla.comma Pla.string
   in
   [%pla{|
   node.controlChange = function(control,value,channel) {
      processor.<#module_name#s>_controlChange(<#ctrl_args#>);
   }
|}]

let get (params:params) runtime code : Pla.t =
   let config = params.config in
   let module_name = params.module_name in
   let nprocess_inputs  = List.length config.process_inputs in
   let nprocess_outputs = List.length config.process_outputs in
   let input_var = List.mapi (fun i _ -> [%pla{|var in_<#i#i> = e.inputBuffer.getChannelData(<#i#i>);|}] ) config.process_inputs |> Pla.join_sep Pla.newline in
   let output_var = List.mapi (fun i _ -> [%pla{|var out_<#i#i> = e.outputBuffer.getChannelData(<#i#i>);|}] ) config.process_outputs |> Pla.join_sep Pla.newline in
   let process_call = performFunctionCall params.module_name params.config in
   let note_on, note_off = noteFunctions params in
   let control_change = controlChangeFunction params in
   let text =
      [%pla {|
(function(audioContext) {
   var code = function () {
      <#runtime#>
      <#code#>
      this.context = this.<#module_name#s>_process_init();
      this.default = function () { this.<#module_name#s>_default(this.context); }
      };
   var processor = new code ();
   var node = audioContext.createScriptProcessor(0, <#nprocess_inputs#i>, <#nprocess_outputs#i>);
   node.inputs = <#nprocess_inputs#i>;
   node.outputs = <#nprocess_outputs#i>;
   node.onaudioprocess = function (e) {
<#input_var#+>
<#output_var#+>
<#process_call#+>
   }
<#note_on#>
<#note_off#>
<#control_change#>
   return node;
   })
|}]
   in
   text