package ar.edu.utn.frc.turnos.service;

import ar.edu.utn.frc.turnos.exception.AppointmentNotFoundException;
import ar.edu.utn.frc.turnos.exception.SlotAlreadyTakenException;
import ar.edu.utn.frc.turnos.model.Appointment;
import ar.edu.utn.frc.turnos.model.AppointmentRequest;
import ar.edu.utn.frc.turnos.model.AppointmentStatus;
import ar.edu.utn.frc.turnos.repository.AppointmentRepository;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AppointmentService {

    private final AppointmentRepository repository;

    public AppointmentService(AppointmentRepository repository) {
        this.repository = repository;
    }

    /** Business rule: a professional cannot have two active appointments in the same slot. */
    @Transactional
    public Appointment create(AppointmentRequest request) {
        boolean taken = repository.existsByProfessionalAndSlotAndStatus(
                request.professional(), request.slot(), AppointmentStatus.ACTIVE);
        if (taken) {
            throw new SlotAlreadyTakenException(
                    request.professional() + " already has an appointment at " + request.slot());
        }
        return repository.save(
                new Appointment(request.professional(), request.patient(), request.slot()));
    }

    public List<Appointment> findAll() {
        return repository.findAll();
    }

    public Appointment findById(Long id) {
        return repository.findById(id).orElseThrow(() -> new AppointmentNotFoundException(id));
    }

    /** Cancelling frees the slot for other patients. */
    @Transactional
    public Appointment cancel(Long id) {
        Appointment appointment = findById(id);
        appointment.cancel();
        return repository.save(appointment);
    }
}
