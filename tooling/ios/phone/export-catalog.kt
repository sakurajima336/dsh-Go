// Run with the repository's unchanged PhoneToolCatalog.kt and Json.kt.
import io.github.sakurajima336.dsh_app.phone.PhoneToolCatalog
import io.github.sakurajima336.dsh_app.phone.Json
fun main() { print(Json.write(PhoneToolCatalog.listJson())) }
