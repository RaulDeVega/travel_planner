-- Creacion de tablas y triggers. 
-- TODO: Revisar los atributos de las tablas y los triggers al tener mejor planteado el proyecto

-- ==========================================
-- TABLAS
-- ==========================================
-- TODO: Decidir si añadir un campo created_at para saber cuando se crearon los datos
-- 1. Tabla Usuario
----------------- TODO: Decidir longitud maxima de datos
CREATE TABLE Usuario (
    idUsuario SERIAL PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    apellidos VARCHAR(255) NOT NULL,
    contraseña VARCHAR(255) NOT NULL, -- Aquí guardaremos el hash de la contraseña
    correo VARCHAR(255) NOT NULL UNIQUE,
    foto_perfil VARCHAR(255) NULL -- Almacena la ruta o el nombre del archivo de la imagen (ej: 'default.jpg')
);

-- 2. Tabla Viaje
----------------- TODO: Decidir longitud maxima de datos
CREATE TABLE Viaje (
    idViaje SERIAL PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT
);

-- 3. Tabla Rol
CREATE TABLE Rol (
    idRol SERIAL PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    CONSTRAINT chk_rol_nombre CHECK (nombre IN ('admin', 'creator', 'miembro'))
);

-- 4. Tabla RolUsuario (Relación Viaje - Usuario - Rol)
CREATE TABLE RolUsuario (
    idViaje INT NOT NULL,
    idUsuario INT NOT NULL,
    idRol INT NOT NULL,
    PRIMARY KEY (idViaje, idUsuario),
    CONSTRAINT fk_rolusuario_viaje FOREIGN KEY (idViaje) REFERENCES Viaje(idViaje) ON DELETE CASCADE,
    CONSTRAINT fk_rolusuario_usuario FOREIGN KEY (idUsuario) REFERENCES Usuario(idUsuario) ON DELETE CASCADE,
    CONSTRAINT fk_rolusuario_rol FOREIGN KEY (idRol) REFERENCES Rol(idRol) ON DELETE CASCADE
);

-- 5. Tabla Itinerario 
-- (Se crea automaticamente al crear un viaje)
CREATE TABLE Itinerario (
    idItinerario SERIAL PRIMARY KEY,
    idViaje INT NOT NULL UNIQUE,
    CONSTRAINT fk_itinerario_viaje FOREIGN KEY (idViaje) REFERENCES Viaje(idViaje) ON DELETE CASCADE
);

-- 6. Tabla Actividad
----------------- TODO: Decidir longitud maxima de datos
CREATE TABLE Actividad (
    idActividad SERIAL PRIMARY KEY,
    idViaje INT NOT NULL,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT,
    fecha TIMESTAMP NULL, -- Puede ser nulo según el esquema
    CONSTRAINT fk_actividad_viaje FOREIGN KEY (idViaje) REFERENCES Viaje(idViaje) ON DELETE CASCADE
);

-- 7. Tabla EntradaItinerario (Relación Itinerario - Actividad)
CREATE TABLE EntradaItinerario (
    idItinerario INT NOT NULL,
    idActividad INT NOT NULL,
    fecha TIMESTAMP NOT NULL,
    PRIMARY KEY (idItinerario, idActividad),
    CONSTRAINT fk_entradaitinerario_itinerario FOREIGN KEY (idItinerario) REFERENCES Itinerario(idItinerario) ON DELETE CASCADE,
    CONSTRAINT fk_entradaitinerario_actividad FOREIGN KEY (idActividad) REFERENCES Actividad(idActividad) ON DELETE CASCADE
);

-- 8. Tabla OpciónVotación
----------------- TODO: Decidir longitud maxima de datos
CREATE TABLE OpcionVotacion (
    idOpcionVotacion SERIAL PRIMARY KEY,
    descripcion TEXT NOT NULL,
    idActividad INT NOT NULL,
    CONSTRAINT fk_opcionvotacion_actividad FOREIGN KEY (idActividad) REFERENCES Actividad(idActividad) ON DELETE CASCADE
);

-- 9. Tabla Voto (Relación OpciónVotación - Usuario)
CREATE TABLE Voto (
    idOpcionVotacion INT NOT NULL,
    idUsuario INT NOT NULL,
    PRIMARY KEY (idOpcionVotacion, idUsuario),
    CONSTRAINT fk_voto_opcionvotacion FOREIGN KEY (idOpcionVotacion) REFERENCES OpcionVotacion(idOpcionVotacion) ON DELETE CASCADE,
    CONSTRAINT fk_voto_usuario FOREIGN KEY (idUsuario) REFERENCES Usuario(idUsuario) ON DELETE CASCADE
);


-- ==========================================
-- TRIGGERS
-- ==========================================

-- 1. Las actividades deben pertenecer al mismo viaje que el itinerario donde se guardan:
CREATE OR REPLACE FUNCTION fn_verificar_misma_viaje_itinerario()
RETURNS TRIGGER AS $$
DECLARE
    v_viaje_itinerario INT;
    v_viaje_actividad INT;
BEGIN
    -- Obtener el viaje del itinerario
    SELECT idViaje INTO v_viaje_itinerario 
    FROM Itinerario 
    WHERE idItinerario = NEW.idItinerario;

    -- Obtener el viaje de la actividad
    SELECT idViaje INTO v_viaje_actividad 
    FROM Actividad 
    WHERE idActividad = NEW.idActividad;

    -- Validar si coinciden
    IF v_viaje_itinerario <> v_viaje_actividad THEN
        RAISE EXCEPTION 'Error de integridad: La actividad (ID %) no pertenece al mismo viaje que el itinerario (ID %).', 
            NEW.idActividad, NEW.idItinerario;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_entrada_itinerario
BEFORE INSERT OR UPDATE ON EntradaItinerario
For EACH ROW
EXECUTE FUNCTION fn_verificar_misma_viaje_itinerario();

-- 2. Pasar direcciones de correo a minusculas:
CREATE OR REPLACE FUNCTION fn_normalizar_correo()
RETURNS TRIGGER AS $$
BEGIN
    NEW.correo := LOWER(TRIM(NEW.correo));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalizar_correo_usuario
BEFORE INSERT OR UPDATE ON Usuario
FOR EACH ROW
EXECUTE FUNCTION fn_normalizar_correo();

-- 3. Crear un itinerario al crear un viaje
CREATE OR REPLACE FUNCTION fn_crear_itinerario_automatico()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Itinerario (idViaje)
    VALUES (NEW.idViaje);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_crear_itinerario
AFTER INSERT ON Viaje
FOR EACH ROW
EXECUTE FUNCTION fn_crear_itinerario_automatico();

-- 4. Solo pueden votar en una actividad los usuarios que forman parte de ese viaje (según RolUsuario):
CREATE OR REPLACE FUNCTION fn_verificar_participante_vota()
RETURNS TRIGGER AS $$
DECLARE
    v_id_viaje INT;
BEGIN
    -- Obtener el idViaje navegando desde la opción de votación hasta la actividad
    SELECT a.idViaje INTO v_id_viaje
    FROM OpcionVotacion ov
    JOIN Actividad a ON ov.idActividad = a.idActividad
    WHERE ov.idOpcionVotacion = NEW.idOpcionVotacion;

    -- Verificar si el usuario tiene algún rol asignado en ese viaje
    IF NOT EXISTS (
        SELECT 1 FROM RolUsuario 
        WHERE idViaje = v_id_viaje AND idUsuario = NEW.idUsuario
    ) THEN
        RAISE EXCEPTION 'Error de votación: El usuario (ID %) no forma parte de este viaje y no puede votar.', NEW.idUsuario;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_voto_participante
BEFORE INSERT OR UPDATE ON Voto
FOR EACH ROW
EXECUTE FUNCTION fn_verificar_participante_vota();


-- ==========================================
-- DATOS INICIALES
-- ==========================================

-- Insertar los roles permitidos por el sistema
INSERT INTO Rol (nombre) VALUES 
    ('admin'),
    ('creator'),
    ('miembro');