package ar.edu.utn.frc.turnos.controller;

import ar.edu.utn.frc.turnos.model.Appointment;
import ar.edu.utn.frc.turnos.model.AppointmentRequest;
import ar.edu.utn.frc.turnos.service.AppointmentService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/appointments")
public class AppointmentController {

    private final AppointmentService service;

    public AppointmentController(AppointmentService service) {
        this.service = service;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Appointment create(@Valid @RequestBody AppointmentRequest request) {
        return service.create(request);
    }

    @GetMapping
    public List<Appointment> list() {
        return service.findAll();
    }

    @GetMapping("/{id}")
    public Appointment get(@PathVariable Long id) {
        return service.findById(id);
    }

    @DeleteMapping("/{id}")
    public Appointment cancel(@PathVariable Long id) {
        return service.cancel(id);
    }
}
