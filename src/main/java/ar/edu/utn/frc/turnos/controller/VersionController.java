package ar.edu.utn.frc.turnos.controller;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class VersionController {

    private final String version;
    private final String environment;

    public VersionController(
            @Value("${app.version}") String version, @Value("${app.env}") String environment) {
        this.version = version;
        this.environment = environment;
    }

    @GetMapping("/api/version")
    public Map<String, String> version() {
        return Map.of("version", version, "env", environment);
    }
}
