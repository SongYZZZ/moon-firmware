///|
/// Process boundary: diagnostics on stderr, distinct diff and error exit codes.
async fn main {
  let args = @env.args()
  let code = @cli.run(@cli.parse_arguments(args[1:].to_owned())) catch {
    @model.FirmwareError(d) => {
      @stdio.stderr.write("error: " + d.render() + "\n") catch {
        _ => ()
      }
      2
    }
    error => {
      @stdio.stderr.write("error: " + error.to_string() + "\n") catch {
        _ => ()
      }
      2
    }
  }
  if code != 0 {
    @sys.exit(code)
  }
}
