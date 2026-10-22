import os
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename
from werkzeug.security import generate_password_hash, check_password_hash

# Carpeta donde se guardarán las fotos (asegúrate de que exista en tu proyecto)
UPLOAD_FOLDER = 'static/uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'} # TODO: ¿Usaremos gif?

# Obtiene la ruta absoluta de la carpeta donde está 'app.py'
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Obtiene la ruta absoluta de la carpeta donde están las imagenes
UPLOAD_FOLDER = os.path.join(BASE_DIR, '../static/img')

# Asegurar que la carpeta exista físicamente al arrancar la app
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = Flask(__name__, 
            template_folder='../templates', 
            static_folder='../static')

# Configuración de la base de datos (lee la variable de entorno de Docker o usa localhost por defecto)
# TODO: asegurarse de que en el docker se pone el mismo nombre de variable para la ruta de init.sql
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get(
    'DATABASE_URL', 
    'postgresql://tu_usuario:tu_password@localhost/tu_base_de_datos'
)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# ==========================================
# MODELOS (Mapeo de tus tablas SQL)
# ==========================================

# TODO: Cambiar si se cambia init.sql
class Usuario(db.Model):
    __tablename__ = 'usuario'
    idUsuario = db.Column(db.Integer, primary_key=True)
    nombre = db.Column(db.String(255), nullable=False)
    apellidos = db.Column(db.String(255), nullable=False)
    contraseña = db.Column(db.String(255), nullable=False)
    correo = db.Column(db.String(255), nullable=False, unique=True)
    foto_perfil = db.Column(db.String(255), nullable=True)

class Viaje(db.Model):
    __tablename__ = 'viaje'
    idViaje = db.Column(db.Integer, primary_key=True)
    nombre = db.Column(db.String(255), nullable=False)
    descripcion = db.Column(db.Text)

class Rol(db.Model):
    __tablename__ = 'rol'
    idRol = db.Column(db.Integer, primary_key=True)
    nombre = db.Column(db.String(50), nullable=False)

class RolUsuario(db.Model):
    __tablename__ = 'rolusuario'
    idViaje = db.Column(db.Integer, db.ForeignKey('viaje.idViaje', ondelete='CASCADE'), primary_key=True)
    idUsuario = db.Column(db.Integer, db.ForeignKey('usuario.idUsuario', ondelete='CASCADE'), primary_key=True)
    idRol = db.Column(db.Integer, db.ForeignKey('rol.idRol', ondelete='CASCADE'), nullable=False)


# ==========================================
# RUTAS DE LA API CON FLASK-SQLALCHEMY
# ==========================================
# TODO: Cambiar si se cambia el init.sql o los archivos html o js.
def archivo_permitido(nombre_archivo):
    return '.' in nombre_archivo and nombre_archivo.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# 1. REGISTRO DE USUARIO
@app.route('/api/register', methods=['POST'])
def register_user():
    nombre = request.form.get('nombre')
    apellidos = request.form.get('apellidos')
    correo = request.form.get('correo')
    contraseña = request.form.get('contraseña')

    # Comprobar que ningún campo obligatorio esté vacío
    if not nombre or not apellidos or not correo or not contraseña:
        return jsonify({"error": "Todos los campos (nombre, apellidos, correo y contraseña) son obligatorios"}), 400
    
    # Manejo de la foto de perfil
    foto = request.files.get('foto_perfil')
    nombre_foto = 'default.jpg' 

    if foto and archivo_permitido(foto.filename):
        nombre_foto = secure_filename(f"{correo}_{foto.filename}")
        
        ruta_guardado = os.path.join(UPLOAD_FOLDER, nombre_foto)
        foto.save(ruta_guardado)

    try:
        nuevo_usuario = Usuario(
            nombre=nombre,
            apellidos=apellidos,
            correo=correo,
            contraseña=contraseña,
            foto_perfil=nombre_foto # En la BD solo guardamos el nombre del archivo
        )
        db.session.add(nuevo_usuario)
        db.session.commit()

        return jsonify({"mensaje": "Usuario registrado con éxito"}), 201

    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 400


# 2. LOGIN DE USUARIO
@app.route('/api/login', methods=['POST'])
def login_user():
    data = request.get_json()
    correo = data.get('correo')
    contraseña = data.get('contraseña')

    # Validar que se envíen ambos campos
    if not correo or not contraseña:
        return jsonify({"error": "El correo y la contraseña son obligatorios"}), 400

    # Buscar al usuario por correo (normalizándolo)
    usuario = Usuario.query.filter(db.func.lower(Usuario.correo) == correo.strip().lower()).first()

    # Avisar si no existe el usuario
    if not usuario:
        return jsonify({"error": "Credenciales inválidas (usuario no encontrado)."}), 401

    # Verificar que la contraseña coincida con el hash guardado en la BD
    # check_password_hash compara la contraseña que escribió el usuario con el hash seguro
    if not check_password_hash(usuario.contraseña, contraseña):
        return jsonify({"error": "Credenciales inválidas (contraseña incorrecta)."}), 401

    # Si todo es correcto, el login es exitoso
    return jsonify({
        "mensaje": "Login exitoso",
        "usuario": {
            "idUsuario": usuario.idUsuario,
            "nombre": usuario.nombre,
            "correo": usuario.correo
        }
    }), 200


# 3. CREAR VIAJE (Y ASIGNAR ROL AL CREADOR)
@app.route('/api/viajes', methods=['POST'])
def create_trip():
    data = request.get_json()
    nombre_viaje = data.get('nombre')
    descripcion = data.get('descripcion')
    id_usuario = data.get('idUsuario')
    rol_nombre = 'creador'

    if not nombre_viaje or not id_usuario:
        return jsonify({"error": "El nombre del viaje y el idUsuario son obligatorios"}), 400

    try:
        # Crear el viaje. 
        # El trigger 'trg_auto_crear_itinerario' creará el itinerario en la BD automáticamente.
        nuevo_viaje = Viaje(nombre=nombre_viaje, descripcion=descripcion)
        db.session.add(nuevo_viaje)
        db.session.flush() # Hace un flush para obtener el idViaje generado antes del commit

        # Buscar obligatoriamente el rol 'creador' en la base de datos
        rol = Rol.query.filter_by(nombre=rol_nombre).first()
        if not rol:
            return jsonify({"error": f"El rol '{rol_nombre}' no está configurado en la base de datos."}), 500

        # Asignar el rol de creador al usuario en ese viaj
        rol_usuario = RolUsuario(
            idViaje=nuevo_viaje.idViaje,
            idUsuario=id_usuario,
            idRol=rol.idRol
        )
        db.session.add(rol_usuario)
        
        db.session.commit()

        return jsonify({
            "mensaje": "Viaje creado con éxito (itinerario generado automáticamente por la BD)",
            "idViaje": nuevo_viaje.idViaje
        }), 201

    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


# 4. LISTAR VIAJES DE UN USUARIO
# TODO: Falta revisar esto
@app.route('/api/usuarios/<int:id_usuario>/viajes', methods=['GET'])
def get_user_trips(id_usuario):
    try:
        # Hacemos la consulta uniendo Viaje, RolUsuario y Rol usando SQLAlchemy
        resultados = db.session.query(Viaje, Rol.nombre.label('rol_usuario')) \
            .join(RolUsuario, Viaje.idViaje == RolUsuario.idViaje) \
            .join(Rol, RolUsuario.idRol == Rol.idRol) \
            .filter(RolUsuario.idUsuario == id_usuario) \
            .all()

        viajes_lista = []
        for viaje, rol_usuario in resultados:
            viajes_lista.append({
                "idViaje": viaje.idViaje,
                "nombre_viaje": viaje.nombre,
                "descripcion": viaje.descripcion,
                "rol_usuario": rol_usuario
            })

        return jsonify({
            "idUsuario": id_usuario,
            "viajes": viajes_lista
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True)